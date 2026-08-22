// The relay's own vocabulary for a citizen report (ábending).
//
// This module and everything above it speaks this vocabulary. The city's field
// names, category slugs and URL are known to exactly one module:
// src/adapters/reykjavik.ts. If any city category slug or endpoint path ever
// appears in code outside that file, that is the bug.
//
// The one value that does cross the API boundary is the category slug: it is
// the only identifier the app has for a category, and the adapter maps it to
// the city's display name, type and summary. The slug values themselves live in
// data/reykjavik-form.json, never hardcoded here.

import { describeAddress } from './registry'
import type { AddressPoint } from './registry'

export interface PhotoPart {
  /** File name as sent by the app. */
  name: string
  /** MIME type; restricted to what the city accepts (see the adapter). */
  mime: string
  bytes: Uint8Array
  size: number
}

export interface ReportDraft {
  /** Category slug, one of the twelve the facts file lists. Validated there. */
  category: string
  latitude: number
  longitude: number
  description: string
  email: string | null
  photos: PhotoPart[]
}

export type Rejection = 'validation' | 'route' | 'error'

export type Outcome = 'fixed' | 'not-fixed'

export interface ReportRecord {
  id: string
  category: string
  latitude: number
  longitude: number
  description: string
  email: string | null
  photoCount: number
  photoBytes: number
  /** True when the city POST was skipped (the safe default). */
  dryRun: boolean
  createdAt: string
  /** When the city POST happened; null while the report is a dry run. */
  sentAt: string | null
  /** Whether the city accepted the report; null until it has been sent. */
  accepted: boolean | null
  cityStatus: number | null
  /** The reference number the city returns (`/done/{number}`); null if unknown. */
  cityReference: string | null
  rejection: Rejection | null
  outcome: Outcome | null
  outcomeAt: string | null
}

/** An error the client can fix; mapped to a 4xx response with `code`. */
export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    readonly extra: Record<string, unknown> = {},
  ) {
    super(code)
  }
}

// ---------------------------------------------------------------------------
// The coordinate guard. The city enforces only `description` (see
// data/reykjavik-form.json, validation.onlyDescriptionIsEnforced), so a report
// with no usable location would be accepted by the city and nobody could act
// on it. The relay rejects it instead.
//
// The input arrives as a multipart string, so this is a strict parse, not a
// Number() coercion: Number("") is 0 and Number("abc") is NaN, and both pass a
// `!= null` check. The regex in scripts/send-report.mjs is the reference — it
// rejects the empty string, NaN, the Icelandic comma ("64,147"), exponents and
// signs. A literal 0 is a finite WGS84 number and passes here; the jurisdiction
// check then refuses it, because 0,0 is nowhere near Reykjavík.
// ---------------------------------------------------------------------------

const DECIMAL = /^-?\d+(\.\d+)?$/

export function readCoordinate(value: unknown, field: 'latitude' | 'longitude'): number {
  if (typeof value !== 'string') {
    throw new HttpError(400, 'invalid-coordinate', { field })
  }
  const v = value.trim()
  if (!DECIMAL.test(v)) {
    throw new HttpError(400, 'invalid-coordinate', { field, reason: 'not a decimal number with a point' })
  }
  const n = Number(v)
  if (!Number.isFinite(n)) {
    throw new HttpError(400, 'invalid-coordinate', { field, reason: 'not a finite number' })
  }
  return n
}

export function assertWgs84(latitude: number, longitude: number): void {
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    throw new HttpError(400, 'invalid-coordinate', {
      reason: 'outside WGS84 bounds',
      latitude,
      longitude,
    })
  }
}

export function readDescription(value: unknown, maxLength: number): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new HttpError(400, 'invalid-description')
  }
  if (value.length > maxLength) {
    throw new HttpError(400, 'invalid-description', { maxLength, got: value.length })
  }
  return value
}

// AGENTS.md: "Put the nearest registered address in the description we send,
// so the crew can find a bin that has no address of its own." The relay adds
// the line because it already reverse-looked the coordinate for jurisdiction;
// the app should not add its own copy. If the line would push the description
// past the city's limit, it is dropped rather than the user's text truncated.
export function composeDescription(
  description: string,
  nearest: AddressPoint | null,
  maxLength: number,
): string {
  if (nearest === null) return description
  const line = `\n\nNæsta skráða heimilisfang: ${describeAddress(nearest)}`
  if (description.length + line.length > maxLength) return description
  return description + line
}
