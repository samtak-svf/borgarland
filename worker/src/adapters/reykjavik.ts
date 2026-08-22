// The ONLY module allowed to know the city's field names, category slugs or
// URL. Everything upstream speaks our own vocabulary (src/domain.ts). If you
// find yourself writing a city field name, slug or path anywhere else, that is
// the bug — see AGENTS.md.
//
// Every fact about the city's form is imported from the repo root's
// data/reykjavik-form.json, the same file scripts/send-report.mjs and
// .github/workflows/contract.yml read. There is deliberately no copy of it
// under worker/: a second copy is a copy that drifts, and restating any of it
// in code would be the same mistake in a different shape. The facts were established by black-box
// probing, not documentation — re-verify with
// `node scripts/send-report.mjs --category <slug> --probe` in the repo root.
//
// This module is the port of scripts/send-report.mjs's payload construction
// and 400 handling. That script is the executable form of
// docs/research/payload-map.md and is the reference this file must stay in
// step with.

import factsJson from '../../../data/reykjavik-form.json'
import type { PhotoPart, ReportDraft } from '../domain'

interface Facts {
  endpoints: { submit: { url: string } }
  categories: { slug: string; type: string; category: string; summary: string }[]
}

const facts = factsJson as unknown as Facts

interface CityCategory {
  slug: string
  type: string
  name: string
  summary: string
}

const CATEGORIES = new Map<string, CityCategory>(
  facts.categories.map((c) => [c.slug, { slug: c.slug, type: c.type, name: c.category, summary: c.summary }]),
)

/** The only way an unknown slug is catchable. The city does NOT 404 on a typo:
 *  it answers 400, the same status as a validation failure — see
 *  docs/research/payload-map.md "An unknown slug does not 404". */
export function isKnownCategory(slug: string): boolean {
  return CATEGORIES.has(slug)
}

export const knownCategorySlugs: readonly string[] = facts.categories.map((c) => c.slug)

// ---------------------------------------------------------------------------
// The payload that would go over the wire, in the city's vocabulary. Only this
// module constructs or names these fields. `url` is what a dry run returns so
// the caller can see exactly what would have been sent and where.
// ---------------------------------------------------------------------------

export interface CityPayloadPhoto {
  name: string
  mime: string
  bytes: Uint8Array
  size: number
}

export interface CityPayload {
  url: string
  fields: {
    type: string
    category: string
    summary: string
    lat: string
    lng: string
    description: string
    email: string | null
  }
  photos: CityPayloadPhoto[]
}

export function buildCityPayload(draft: ReportDraft): CityPayload {
  const category = CATEGORIES.get(draft.category)
  if (!category) {
    // Unreachable through the relay (it validates first), but this module
    // cannot be asked to build a payload for a slug it does not know.
    throw new Error(`unknown category slug: ${draft.category}`)
  }
  return {
    url: facts.endpoints.submit.url.replace('{slug}', draft.category),
    fields: {
      type: category.type,
      category: category.name,
      summary: category.summary,
      lat: String(draft.latitude),
      lng: String(draft.longitude),
      description: draft.description,
      email: draft.email,
    },
    photos: draft.photos.map((p: PhotoPart) => ({ name: p.name, mime: p.mime, bytes: p.bytes, size: p.size })),
  }
}

export type CitySubmitOutcome =
  | { status: 'accepted'; reference: string | null }
  | { status: 'rejected'; reason: 'validation' | 'route'; httpStatus: number }
  | { status: 'error'; httpStatus: number }

// The success signal the city gives is a navigation to
// .../senda-abendingu/{slug}/done/{number} (facts.endpoints.submit.successResponse).
// The raw POST response body was never captured on success — the only real
// success was observed in a browser. Extracting the number with /done/(\d+) is
// the honest attempt; when it does not match we still treat a 2xx as accepted
// but record a null reference. [GUESS — see WORKER-NOTES.md]
const DONE_REFERENCE = /done\/(\d+)/

/**
 * POST the payload to the city. The 400 handling mirrors scripts/send-report.mjs
 * exactly:
 *
 *  - 400 + "Missing required fields" + the category hidden field re-rendered
 *    (`value="<display name>"`) = a real validation failure;
 *  - 400 without that envelope = the route did not match (unknown slug, or the
 *    city changed the path). The city answers 400 to an unknown slug too, so
 *    status alone cannot tell the two apart.
 *
 * The backslash-heavy shapes in scripts/send-report.mjs are deliberate: the
 * route answers React Router turbo-stream, i.e. escaped JSON embedded in the
 * re-rendered HTML page, so the error payload literally contains \"description\"
 * with backslashes. The discriminator here uses the unescaped envelope plus the
 * re-rendered hidden field, exactly as the script's main flow does.
 */
export async function submitCityPayload(
  payload: CityPayload,
  fetchImpl: typeof fetch,
): Promise<CitySubmitOutcome> {
  const fd = new FormData()
  fd.set('type', payload.fields.type)
  fd.set('category', payload.fields.category)
  fd.set('summary', payload.fields.summary)
  fd.set('lat', payload.fields.lat)
  fd.set('lng', payload.fields.lng)
  fd.set('description', payload.fields.description)
  if (payload.fields.email) fd.set('email', payload.fields.email)
  for (const photo of payload.photos) {
    fd.append('files', new File([photo.bytes], photo.name, { type: photo.mime }))
  }

  const response = await fetchImpl(payload.url, { method: 'POST', body: fd })
  const text = await response.text()

  if (response.status === 400) {
    const validated =
      text.includes('Missing required fields') && text.includes(`value="${payload.fields.category}"`)
    return {
      status: 'rejected',
      reason: validated ? 'validation' : 'route',
      httpStatus: response.status,
    }
  }
  if (!response.ok) {
    return { status: 'error', httpStatus: response.status }
  }
  const match = text.match(DONE_REFERENCE)
  return { status: 'accepted', reference: match?.[1] ?? null }
}
