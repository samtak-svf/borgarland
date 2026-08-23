// The adapter is the only module allowed to know the city's field names,
// slugs or URL. These tests pin the mapping from our vocabulary to the city's
// and the 400 discriminator that separates a validation failure from an
// unknown route (the city answers 400 to both — see
// docs/research/payload-map.md "An unknown slug does not 404").

import { describe, expect, it } from 'vitest'
import type { ReportDraft } from '../../src/domain'
import {
  buildCityPayload,
  isKnownCategory,
  knownCategorySlugs,
  submitCityPayload,
} from '../../src/adapters/reykjavik'
import { createRegistry } from '../../src/registry'
import { checkJurisdiction, MAX_NEAREST_ADDRESS_KM } from '../../src/jurisdiction'
import { describeAddress } from '../../src/registry'
import { FIXTURE_ADDRESSES } from '../helpers/fixtures'

const draft: ReportDraft = {
  category: 'ruslafotur',
  latitude: 64.14658919,
  longitude: -21.93279823,
  description: 'Full ruslafata við stíginn',
  email: 'test@example.com',
  photos: [{ name: 'bin.jpg', mime: 'image/jpeg', bytes: new Uint8Array([1, 2, 3]), size: 3 }],
}

// The city's validation 400: the "Missing required fields" envelope plus the
// re-rendered form with the category hidden field filled in. The backslash
// shapes are faithful to the React Router turbo-stream response (escaped JSON
// inside the HTML) — see scripts/send-report.mjs's probe.
const VALIDATION_400 =
  '<html><body><div id="root">{\\"error\\":\\"Missing required fields\\",\\"inputErrors\\":{\\"description\\":[\\"Vinsamlegast skrifaðu lýsingu á málinu.\\"]}}</div>' +
  '<form><input type="hidden" name="category" value="Ruslafötur"/><input name="description" value=""/></form></body></html>'

// An unknown slug on the Icelandic path: the city answers 400 with a "page not
// found" page, no validator envelope, no re-rendered form.
const ROUTE_400 =
  '<!doctype html><html><head><title>Síða fannst ekki (404)</title></head>' +
  '<body><h1>404</h1><p>Síða fannst ekki</p></body></html>'

const SUCCESS_200 =
  '<html><body><h1>Þakkir fyrir ábendinguna</h1>' +
  '<p>Málsnúmer: 110999</p>' +
  '<a href="/abendingar/senda-abendingu/ruslafotur/done/110999">Sjá stöðu</a></body></html>'

function stub(body: string, status: number) {
  return async () => new Response(body, { status })
}

describe('category knowledge comes from data/reykjavik-form.json', () => {
  it('knows the twelve Icelandic slugs and rejects English/nonsense ones', () => {
    expect(isKnownCategory('ruslafotur')).toBe(true)
    expect(isKnownCategory('almenn-abending')).toBe(true)
    expect(isKnownCategory('bilastaedasjodur')).toBe(true)
    // The English form has its own slugs; posting them to the Icelandic path
    // gets a 400 with a 404 page. We reject them before sending.
    expect(isKnownCategory('waste-bins')).toBe(false)
    expect(isKnownCategory('nonsense')).toBe(false)
    expect(knownCategorySlugs).toHaveLength(12)
  })
})

describe('buildCityPayload maps our vocabulary to the city field values', () => {
  it('maps ruslafotur to its fixed type, display name and summary', () => {
    const payload = buildCityPayload(draft)
    expect(payload.fields).toEqual({
      type: 'specific',
      category: 'Ruslafötur',
      summary: 'Ábending -> Ruslafötur',
      lat: '64.14658919',
      lng: '-21.93279823',
      description: 'Full ruslafata við stíginn',
      email: 'test@example.com',
    })
    expect(payload.url).toContain('ruslafotur')
    expect(payload.photos).toEqual([
      { name: 'bin.jpg', mime: 'image/jpeg', bytes: new Uint8Array([1, 2, 3]), size: 3 },
    ])
  })

  it('maps almenn-abending as general, the only structural difference', () => {
    const payload = buildCityPayload({ ...draft, category: 'almenn-abending' })
    expect(payload.fields.type).toBe('general')
    expect(payload.fields.category).toBe('Almenn ábending')
    expect(payload.fields.summary).toBe('Ábending -> Almenn ábending')
  })

  it('refuses to build a payload for a slug it does not know', () => {
    expect(() => buildCityPayload({ ...draft, category: 'nonsense' })).toThrow(/unknown category/)
  })
})

describe('submitCityPayload', () => {
  it('builds the city multipart with the city field names', async () => {
    // An array capture: closure-assigned `let`s narrow to never under TS 6's
    // control-flow analysis, so the stub pushes into an array instead.
    const seen: ({ url: string; fd: FormData } | null)[] = []
    const fetchImpl = async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url
      seen.push({ url, fd: await new Request(url, init).formData() })
      return new Response(SUCCESS_200, { status: 200 })
    }
    const outcome = await submitCityPayload(buildCityPayload(draft), fetchImpl)
    expect(outcome).toEqual({ status: 'accepted', reference: '110999' })
    const first = seen[0]
    expect(first?.url).toContain('/abendingar/senda-abendingu/ruslafotur')
    expect(first?.fd.get('type')).toBe('specific')
    expect(first?.fd.get('category')).toBe('Ruslafötur')
    expect(first?.fd.get('summary')).toBe('Ábending -> Ruslafötur')
    expect(first?.fd.get('lat')).toBe('64.14658919')
    expect(first?.fd.get('lng')).toBe('-21.93279823')
    expect(first?.fd.get('description')).toBe('Full ruslafata við stíginn')
    expect(first?.fd.get('email')).toBe('test@example.com')
    const files = first?.fd.getAll('files') ?? []
    expect(files).toHaveLength(1)
    expect(files[0]).toBeInstanceOf(File)
    expect((files[0] as File).name).toBe('bin.jpg')
    expect((files[0] as File).type).toBe('image/jpeg')
  })

  it('classifies the validation 400 by the Missing required fields envelope', async () => {
    const outcome = await submitCityPayload(buildCityPayload(draft), stub(VALIDATION_400, 400))
    expect(outcome).toEqual({ status: 'rejected', reason: 'validation', httpStatus: 400 })
  })

  it('classifies an unknown-route 400 (no validator envelope) separately', async () => {
    const outcome = await submitCityPayload(buildCityPayload(draft), stub(ROUTE_400, 400))
    expect(outcome).toEqual({ status: 'rejected', reason: 'route', httpStatus: 400 })
  })

  it('reports an unexpected status as an error', async () => {
    const outcome = await submitCityPayload(buildCityPayload(draft), stub('boom', 500))
    expect(outcome).toEqual({ status: 'error', httpStatus: 500 })
  })

  it('treats a 2xx without a done/ number as accepted with an unknown reference', async () => {
    const outcome = await submitCityPayload(
      buildCityPayload(draft),
      stub('<html><body>takk</body></html>', 200),
    )
    expect(outcome).toEqual({ status: 'accepted', reference: null })
  })

  it('omits the email part when there is none', async () => {
    const seen: (FormData | null)[] = []
    const fetchImpl = async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url
      seen.push(await new Request(url, init).formData())
      return new Response(SUCCESS_200, { status: 200 })
    }
    await submitCityPayload(buildCityPayload({ ...draft, email: null }), fetchImpl)
    expect(seen[0]?.has('email')).toBe(false)
  })
})

describe('jurisdiction reads SVFNR of the nearest registered address', () => {
  const registry = createRegistry(FIXTURE_ADDRESSES)

  it('passes a point whose nearest address is in Reykjavík (SVFNR 0000)', () => {
    const check = checkJurisdiction(registry, 64.14658919, -21.93279823)
    expect(check).toMatchObject({ ok: true })
  })

  it('refuses a Kópavogur point (SVFNR 1000) with the nearest address named', () => {
    const check = checkJurisdiction(registry, 64.1109, -21.901)
    expect(check).toMatchObject({ ok: false, reason: 'outside-reykjavik' })
    if (!check.ok && check.reason === 'outside-reykjavik') {
      expect(describeAddress(check.nearest)).toBe('Hamraborg 3, 200 Kópavogur')
    }
  })

  it('fails closed when the registry holds nothing at all', () => {
    const check = checkJurisdiction(createRegistry([]), 64.14, -21.93)
    expect(check).toEqual({ ok: false, reason: 'unknown', nearest: null, km: null })
  })

  // #75. The register holds Icelandic addresses only, so the nearest-address
  // scan answers for every point on Earth: a coordinate in Seattle resolved to
  // a lighthouse in Suðureyri and the answer said nothing about the 5,630 km
  // between them.
  it('refuses a coordinate too far from any registered address, and offers no address for it', () => {
    const check = checkJurisdiction(registry, 47.64, -122.4)
    expect(check).toMatchObject({ ok: false, reason: 'unknown', nearest: null })
    expect(check.km).toBeGreaterThan(1000)
  })

  it('keeps the bound generous enough for anywhere in Reykjavík', () => {
    // Kjalarnes is the farthest point inside the municipality measured against
    // the 139,360-row snapshot, at 3.31 km from a registered address, and the
    // bound is 10.
    expect(MAX_NEAREST_ADDRESS_KM).toBeGreaterThanOrEqual(10)
  })

  /**
   * The limitation, pinned rather than hidden. A point register cannot answer a
   * polygon question: a coordinate the wrong side of a boundary whose nearest
   * registered address is still a Reykjavík one passes, and the distance bound
   * does not change that. Only the boundaries themselves would.
   */
  it('passes a point outside Reykjavík whose nearest registered address is inside it', () => {
    const justOutside = createRegistry([
      { svfnr: 0, streetNf: 'Reykjavíkurgata', houseNumber: 1, houseLetter: null, postalCode: '101', lat: 64.14, lng: -21.93 },
      { svfnr: 1000, streetNf: 'Kópavogsgata', houseNumber: 1, houseLetter: null, postalCode: '200', lat: 64.10, lng: -21.90 },
    ])
    // Nearer to the Reykjavík row than to the Kópavogur one, and the check
    // says yes. This is a known limitation, not a passing test of correctness.
    const check = checkJurisdiction(justOutside, 64.135, -21.925)
    expect(check.ok).toBe(true)
  })
})
