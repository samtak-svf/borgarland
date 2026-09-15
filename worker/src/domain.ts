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
  /**
   * Where the city sends its confirmation, and the only channel it has back to
   * the person who filed (#163). It lives on the DRAFT and never on the
   * record: it is forwarded to the city and kept nowhere, the same rule the
   * photo bytes have.
   */
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
  /** Which build filed the report, parsed from the app's User-Agent (#186). Null for a non-app sender. */
  appVersion: string | null
  /** Per photo: the declared MIME and the sniffed one (#186). Null for a row written before the columns existed. */
  photoMimes: { declared: string; actual: string }[] | null
  /** What would have gone over the wire, photos summarized and the email removed (#186). */
  cityPayload: Record<string, unknown> | null
  /** How far the nearest registered address was, in kilometres (#186). */
  jurisdictionKm: number | null
  /** Which launch of the app filed this, joining the report to its telemetry walk (#186). Null for a row written before the column existed. */
  session: string | null
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

/** Where the report is, as far as the appended block needs to know (#202). */
export interface ReportLocation {
  /** The nearest registered address, or null when the register knows of none. */
  nearest: AddressPoint | null
  /** How far that address is from the coordinate, in kilometres. */
  nearestKm: number
  latitude: number
  longitude: number
}

// AGENTS.md: "Put the nearest registered address in the description we send,
// so the crew can find a bin that has no address of its own." The relay adds
// the block because it already reverse-looked the coordinate for jurisdiction;
// the app should not add its own copy. If the block would push the description
// past the city's limit, it is dropped rather than the user's text truncated.
//
// The block says THREE things, and the first two are #202. An address alone was
// read as the location: "Næsta skráða heimilisfang: Gullengi 37" reached a crew
// who had no way to know it is a lookup result and not where the reporter
// stood — the exact reading the coordinate-first design exists to avoid, and
// the city's answer to report 110759 came back naming a neighbouring house
// rather than the place. So the line now names the register it came from and
// how far away it was, and the coordinate the lookup was run against is
// printed under it.
//
// The coordinate is `String(latitude)`, the same expression the adapter uses
// for the city's own `lat`/`lng` fields, so the text and the fields cannot
// disagree — they are one number formatted one way. Period decimal separator,
// latitude first, comma and space between: a coordinate is a number a device
// reads, and the Icelandic decimal comma is not what any map takes. Deliberately
// not a `geo:` URI or a maps link, because the city stores this text and quotes
// it back in its closing email (data/reykjavik-form.json
// `fields.email.answerEmail`), and a link in a stored message that may not be
// clickable is worse than a pair of numbers the reader can type.
export function composeDescription(
  description: string,
  location: ReportLocation,
  maxLength: number,
): string {
  const lines: string[] = []
  if (location.nearest !== null) {
    lines.push(
      `Næsta skráða heimilisfang í Staðfangaskrá: ${describeAddress(location.nearest)}, ` +
        `${describeDistance(location.nearestKm)} frá hnitinu.`,
    )
  }
  lines.push(`Hnit: ${location.latitude}, ${location.longitude}`)
  const block = `\n\n${lines.join('\n')}`
  if (description.length + block.length > maxLength) return description
  return description + block
}

/**
 * The distance to the nearest registered address, in the unit a reader can act
 * on (#202): metres below a kilometre, kilometres above it, and Icelandic
 * decimal commas, because this sentence is addressed to a person.
 *
 * Ten-metre rounding below a kilometre, and a floor that says so rather than
 * rounding to nothing, because the fix it was measured from carries metres of
 * its own — the photograph measured in docs/research/photos-exif-and-formats.md
 * declared an accuracy of 3.54 m. A figure finer than its input would claim an
 * accuracy nobody has.
 */
function describeDistance(km: number): string {
  const metres = Math.round(km * 1000)
  if (metres < 1000) {
    if (metres < 10) return 'minna en 10 m'
    return `${Math.round(metres / 10) * 10} m`
  }
  return `${(Math.round(km * 10) / 10).toFixed(1).replace('.', ',')} km`
}
