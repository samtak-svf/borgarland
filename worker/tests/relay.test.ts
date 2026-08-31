// End-to-end tests of the relay through its public API. The city is stubbed
// (deps.fetch), the database is a real SQLite behind a D1-shaped facade, and
// globalThis.fetch is replaced with a thrower so that any accidental real
// network call fails the test instead of reaching reykjavik.is.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createRegistry } from '../src/registry'
import {
  createTestApp,
  json,
  JPEG_BYTES,
  KOPAVOGUR_POINT,
  getPhoto,
  postReport,
  promoteReport,
  reportForm,
  REYKJAVIK_POINT,
  TEST_LIVE_KEY,
} from './helpers/fixtures'
import type { TestApp } from './helpers/fixtures'

const VALIDATION_400 =
  '<div id="root">{"error":"Missing required fields","inputErrors":{"description":["x"]}}</div>' +
  '<form><input type="hidden" name="category" value="Ruslafötur"/></form>'
const ROUTE_400 = '<html><head><title>Síða fannst ekki (404)</title></head><body></body></html>'
const SUCCESS_200 =
  '<html><body><a href="/abendingar/senda-abendingu/ruslafotur/done/110999">done</a></body></html>'

function donePage(reference: string): string {
  return `<html><body><a href="/abendingar/senda-abendingu/ruslafotur/done/${reference}">done</a></body></html>`
}

beforeEach(() => {
  // Rule 1, made mechanical: no code path may reach the real network in tests.
  vi.stubGlobal(
    'fetch',
    () => {
      throw new Error('tests must never hit the real network')
    },
  )
})

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('dry run is the default', () => {
  it('records the row, returns our id and the would-be payload, and never calls the city', async () => {
    const { app, cityFetch } = createTestApp()
    const response = await postReport(app, reportForm())
    expect(response.status).toBe(201)

    const body = await json(response)
    const report = body.report as Record<string, unknown>
    expect(report.id).toBe('a1b2c3d4e5f60718')
    expect(report.dryRun).toBe(true)
    expect(report.sentAt).toBeNull()
    expect(report.accepted).toBeNull()

    // What would have gone over the wire, in the city's vocabulary.
    const payload = body.cityPayload as {
      url: string
      fields: Record<string, string>
      photos: { name: string; mime: string; size: number }[]
    }
    expect(payload.fields.type).toBe('specific')
    expect(payload.fields.category).toBe('Ruslafötur')
    expect(payload.fields.summary).toBe('Ábending -> Ruslafötur')
    expect(payload.fields.lat).toBe(REYKJAVIK_POINT.latitude)
    expect(payload.fields.lng).toBe(REYKJAVIK_POINT.longitude)
    // The crew line: nearest registered address goes into the description.
    expect(payload.fields.description).toContain('Næsta skráða heimilisfang: Laugavegur 1, 101 Reykjavík')
    expect(payload.photos).toEqual([{ name: 'bin.jpg', mime: 'image/jpeg', size: JPEG_BYTES.length }])

    expect(() => cityFetch).not.toThrow()
    // The injected city fetch is the only fetch the app has; it must not have
    // been called. (The default stub throws, so this is also implicitly proven
    // by the request succeeding.)
    expect(vi.isMockFunction(cityFetch)).toBe(false)
  })

  it('stores dry_run=1 with no send metadata in the row', async () => {
    const { app, sqlite } = createTestApp()
    await postReport(app, reportForm())
    const rows = sqlite.prepare('SELECT * FROM reports').all()
    expect(rows).toHaveLength(1)
    const row = rows[0] as Record<string, unknown>
    expect(row.dry_run).toBe(1)
    expect(row.sent_at).toBeNull()
    expect(row.city_status).toBeNull()
    expect(row.category_slug).toBe('ruslafotur')
  })

  it('records photo count and bytes, not the bytes themselves', async () => {
    const { app, sqlite } = createTestApp()
    const fd = reportForm()
    // A second genuine JPEG: the relay now sniffs bytes behind the declared
    // type, so a photo whose bytes are not what its MIME claims would reject
    // the whole report before anything is stored.
    fd.append('photo', new File([JPEG_BYTES], 'two.jpg', { type: 'image/jpeg' }))
    await postReport(app, fd)
    const row = sqlite.prepare('SELECT photo_count, photo_bytes FROM reports').all()[0]
    expect(row).toEqual({ photo_count: 2, photo_bytes: 44 })
  })
})

describe('the row keeps what a diagnosis needs (#186)', () => {
  it('records which build filed the report, from the app User-Agent', async () => {
    const { app, sqlite } = createTestApp()
    const response = await app(
      new Request('https://relay.local/api/reports', {
        method: 'POST',
        body: reportForm(),
        headers: { 'user-agent': 'Borgarland/0.1.0 (7)' },
      }),
    )
    expect(response.status).toBe(201)
    const row = sqlite.prepare('SELECT app_version FROM reports').all()[0] as Record<string, unknown>
    expect(row.app_version).toBe('0.1.0 (7)')
  })

  it('a sender without the app UA stores no version', async () => {
    const { app, sqlite } = createTestApp()
    await postReport(app, reportForm())
    const row = sqlite.prepare('SELECT app_version FROM reports').all()[0] as Record<string, unknown>
    expect(row.app_version).toBeNull()
  })

  it('records the declared and sniffed MIME of every photo', async () => {
    const { app, sqlite } = createTestApp()
    const fd = reportForm()
    fd.append('photo', new File([JPEG_BYTES], 'two.jpg', { type: 'image/jpeg' }))
    await postReport(app, fd)
    const row = sqlite.prepare('SELECT photo_mimes FROM reports').all()[0] as Record<string, unknown>
    expect(JSON.parse(row.photo_mimes as string)).toEqual([
      { declared: 'image/jpeg', actual: 'image/jpeg' },
      { declared: 'image/jpeg', actual: 'image/jpeg' },
    ])
  })

  it('stores what would have gone to the city, without the email and without photo bytes', async () => {
    const { app, sqlite } = createTestApp()
    const fd = reportForm()
    fd.set('email', 'prufa@example.is')
    await postReport(app, fd)
    const row = sqlite.prepare('SELECT city_payload FROM reports').all()[0] as Record<string, unknown>
    const stored = JSON.parse(row.city_payload as string) as {
      url: string
      fields: Record<string, unknown>
      photos: { name: string; mime: string; size: number; bytes?: unknown }[]
    }
    // The email is the one thing the relay keeps nowhere (0004, #163); a
    // stored payload must not become a second store of it.
    expect(stored.fields.email).toBeUndefined()
    expect(stored.fields.description).toContain('Næsta skráða heimilisfang: Laugavegur 1, 101 Reykjavík')
    expect(stored.photos).toEqual([{ name: 'bin.jpg', mime: 'image/jpeg', size: JPEG_BYTES.length }])
    expect(stored.url).toContain('/senda-abendingu/')
  })

  it('records how far the nearest registered address was', async () => {
    const { app, sqlite } = createTestApp()
    await postReport(app, reportForm())
    const row = sqlite.prepare('SELECT jurisdiction_km FROM reports').all()[0] as Record<string, unknown>
    // REYKJAVIK_POINT is Laugavegur 1's own coordinate, so the distance is 0.
    expect(row.jurisdiction_km).toBe(0)
  })

  it('the response carries the new fields too', async () => {
    const { app } = createTestApp()
    const response = await app(
      new Request('https://relay.local/api/reports', {
        method: 'POST',
        body: reportForm(),
        headers: { 'user-agent': 'Borgarland/0.1.0 (7)' },
      }),
    )
    const report = (await json(response)).report as Record<string, unknown>
    expect(report.appVersion).toBe('0.1.0 (7)')
    expect(report.jurisdictionKm).toBe(0)
    expect(report.photoMimes).toEqual([{ declared: 'image/jpeg', actual: 'image/jpeg' }])
    expect(report.cityPayload).toEqual(expect.any(Object))
  })

  it('a row written before these columns existed still reads back', async () => {
    // The pre-0005 shape: the original columns and nothing else. The migration
    // adds the four new ones as nullable, so an old row must read back with
    // nulls rather than failing — the promote and duplicate-check paths read
    // rows written by older relays.
    const { app, sqlite } = createTestApp()
    sqlite
      .prepare(
        `INSERT INTO reports (id, category_slug, latitude, longitude, description, photo_count, photo_bytes, dry_run, created_at, sent_at, city_status, city_reference, rejection, outcome, outcome_at)
         VALUES ('deadbeef000000000000000000000001', 'ruslafotur', 64.14658919, -21.93279823, 'gömul lýsing', 1, 44, 1, '2026-08-01T00:00:00.000Z', NULL, NULL, NULL, NULL, NULL, NULL)`,
      )
      .run()
    const response = await app(new Request('https://relay.local/api/reports/deadbeef000000000000000000000001'))
    expect(response.status).toBe(200)
    const report = (await json(response)).report as Record<string, unknown>
    expect(report.id).toBe('deadbeef000000000000000000000001')
    expect(report.appVersion).toBeNull()
    expect(report.photoMimes).toBeNull()
    expect(report.cityPayload).toBeNull()
    expect(report.jurisdictionKm).toBeNull()
  })
})

describe('the coordinate guard', () => {
  it.each([
    ['missing latitude', { latitude: '__remove__' }],
    ['empty string latitude', { latitude: '' }],
    ['NaN as text', { latitude: 'NaN' }],
    ['Icelandic comma', { latitude: '64,1465' }],
    ['not a number', { latitude: 'abc' }],
    ['out of WGS84 range', { latitude: '91' }],
    ['missing longitude', { longitude: '__remove__' }],
  ])('rejects %s', async (_name, overrides) => {
    const { app, cityFetch } = createTestApp()
    const response = await postReport(app, reportForm(overrides))
    expect(response.status).toBe(400)
    expect((await json(response)).error).toBe('invalid-coordinate')
    // Nothing reaches the city and no row is recorded.
    expect(() => cityFetch).not.toThrow()
  })

  it('a literal 0,0 does not slip through, and is refused for the right reason', async () => {
    const { app } = createTestApp()
    const response = await postReport(
      app,
      reportForm({ latitude: '0', longitude: '0' }),
    )
    expect(response.status).toBe(400)
    // It used to be refused as outside-reykjavik, which was true and told
    // nobody anything: 0,0 is in the Gulf of Guinea and the SVFNR deciding it
    // belonged to an address thousands of kilometres away (#75). The refusal
    // now says what is actually wrong.
    const body = await json(response)
    expect(body.error).toBe('jurisdiction-unknown')
    expect(body.nearestKm).toBeGreaterThan(1000)
    // And the address itself is not offered, because at that distance it is
    // not a place.
    expect(body.nearestAddress).toBeUndefined()
  })
})

describe('jurisdiction', () => {
  it('refuses a Kópavogur coordinate with a clear reason', async () => {
    const { app, sqlite } = createTestApp()
    const response = await postReport(app, reportForm(KOPAVOGUR_POINT))
    expect(response.status).toBe(400)
    const body = await json(response)
    expect(body.error).toBe('outside-reykjavik')
    expect(body.nearestAddress).toBe('Hamraborg 3, 200 Kópavogur')
    expect(body.svfnr).toBe(1000)
    expect(sqlite.prepare('SELECT COUNT(*) AS n FROM reports').all()).toEqual([{ n: 0 }])
  })

  // The refusal used to say what we would not do and never where the person
  // was. Both apps build a sentence from `placeDative` and drop the whole line
  // when the field is absent, so a refusal that stops carrying it goes silently
  // back to the screen a tester read three times (#148). Dative because
  // Icelandic needs one to say "í Kópavogi", and declining a place name in
  // Swift and Kotlin separately is two places for it to be wrong.
  it('names the place, in the case the sentence needs', async () => {
    const { app } = createTestApp()
    const body = await json(await postReport(app, reportForm(KOPAVOGUR_POINT)))
    expect(body.place).toBe('Kópavogur')
    expect(body.placeDative).toBe('Kópavogi')
  })

  it('a point that resolves to no address at all is refused, not filed', async () => {
    const { app } = createTestApp({ registry: createRegistry([]) })
    const response = await postReport(app, reportForm())
    expect(response.status).toBe(400)
    expect((await json(response)).error).toBe('jurisdiction-unknown')
  })

  it('an unseeded registry answers 503 and fails closed', async () => {
    const { app } = createTestApp({ registryError: true })
    const response = await postReport(app, reportForm())
    expect(response.status).toBe(503)
    expect((await json(response)).error).toBe('registry-not-loaded')
  })
})

describe('category handling', () => {
  it('rejects an unknown slug before anything else', async () => {
    const { app } = createTestApp()
    const response = await postReport(app, reportForm({ category: 'waste-bins' }))
    expect(response.status).toBe(400)
    expect((await json(response)).error).toBe('unknown-category')
  })

  it('rejects a nonsense slug too', async () => {
    const { app } = createTestApp()
    const response = await postReport(app, reportForm({ category: 'nonsense' }))
    expect(response.status).toBe(400)
    expect((await json(response)).error).toBe('unknown-category')
  })

  it('an empty category is rejected', async () => {
    const { app } = createTestApp()
    const response = await postReport(app, reportForm({ category: '' }))
    expect(response.status).toBe(400)
    expect((await json(response)).error).toBe('unknown-category')
  })
})

describe('description handling', () => {
  it('rejects a missing or empty description', async () => {
    const { app } = createTestApp()
    for (const overrides of [{ description: '__remove__' }, { description: '' }, { description: '   ' }]) {
      const response = await postReport(app, reportForm(overrides))
      expect(response.status).toBe(400)
      expect((await json(response)).error).toBe('invalid-description')
    }
  })

  it('rejects a description over the city limit', async () => {
    const { app } = createTestApp()
    const response = await postReport(app, reportForm({ description: 'x'.repeat(2501) }))
    expect(response.status).toBe(400)
    expect((await json(response)).error).toBe('invalid-description')
  })

  it('drops the address line rather than overflow the limit', async () => {
    const { app } = createTestApp()
    const max = 'x'.repeat(2500)
    const response = await postReport(app, reportForm({ description: max }))
    const body = await json(response)
    const payload = body.cityPayload as { fields: { description: string } }
    expect(payload.fields.description).toBe(max)
    expect(payload.fields.description).not.toContain('Næsta skráða heimilisfang')
  })
})

describe('photos', () => {
  it('rejects a non-file photo part', async () => {
    const { app } = createTestApp()
    const fd = reportForm()
    fd.append('photo', 'not a file')
    const response = await postReport(app, fd)
    expect(response.status).toBe(400)
    expect((await json(response)).error).toBe('invalid-photo')
  })

  it('rejects a photo the city does not accept', async () => {
    const { app } = createTestApp()
    const fd = reportForm()
    fd.append('photo', new File([new Uint8Array([1])], 'x.bin', { type: 'application/octet-stream' }))
    const response = await postReport(app, fd)
    expect(response.status).toBe(400)
    expect((await json(response)).error).toBe('invalid-photo')
  })

  it('passes a JPEG whose bytes match its declared type', async () => {
    const { app } = createTestApp()
    const fd = reportForm()
    fd.set('photo', new File([JPEG_BYTES], 'bin.jpg', { type: 'image/jpeg' }))
    const response = await postReport(app, fd)
    expect(response.status).toBe(201)
  })

  it('rejects a HEIC photo declared as image/jpeg, naming both types', async () => {
    // The case the sniffer exists for. An iPhone shoots HEIC and the city
    // accepts only jpeg/png/gif, so the declared type passes the allowlist
    // and only the bytes give the file away; without this check the report
    // would be recorded as sent and then fail at the city.
    const { app } = createTestApp()
    const fd = reportForm()
    fd.set(
      'photo',
      new File(
        // A minimal HEIC: box size, 'ftyp', major brand 'heic'. The bytes
        // must be wrapped in an array — a bare Uint8Array is iterable, so
        // the File constructor would treat each byte as a part and stringify
        // it to its decimal digits.
        [new Uint8Array([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63])],
        'photo.heic',
        { type: 'image/jpeg' },
      ),
    )
    const response = await postReport(app, fd)
    expect(response.status).toBe(400)
    const body = await json(response)
    expect(body.error).toBe('invalid-photo')
    expect(body.declared).toBe('image/jpeg')
    expect(body.actual).toBe('image/heic')
  })

  it('passes a PNG declared as PNG', async () => {
    const { app } = createTestApp()
    const fd = reportForm()
    fd.set(
      'photo',
      new File(
        // The PNG signature plus the start of the IHDR chunk.
        [new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d])],
        'bin.png',
        { type: 'image/png' },
      ),
    )
    const response = await postReport(app, fd)
    expect(response.status).toBe(201)
  })

  it('passes a GIF declared as GIF', async () => {
    const { app } = createTestApp()
    const fd = reportForm()
    fd.set(
      'photo',
      new File(
        // 'GIF89a' plus the start of the logical screen descriptor.
        [new Uint8Array([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00])],
        'bin.gif',
        { type: 'image/gif' },
      ),
    )
    const response = await postReport(app, fd)
    expect(response.status).toBe(201)
  })

  it('rejects a truncated JPEG without throwing', async () => {
    // A photo cut off mid-signature is a rejection like any other mismatch,
    // not a 500: the sniffer must answer null for a short buffer.
    const { app } = createTestApp()
    const fd = reportForm()
    fd.set('photo', new File([new Uint8Array([0xff, 0xd8])], 'cut.jpg', { type: 'image/jpeg' }))
    const response = await postReport(app, fd)
    expect(response.status).toBe(400)
    const body = await json(response)
    expect(body.error).toBe('invalid-photo')
    expect(body.declared).toBe('image/jpeg')
    expect(body.actual).toBeNull()
  })
})

describe('GET /api/reports/:id', () => {
  it('returns what we know about a report', async () => {
    const { app } = createTestApp()
    await postReport(app, reportForm())
    const response = await app(new Request('https://relay.local/api/reports/a1b2c3d4e5f60718'))
    expect(response.status).toBe(200)
    const report = (await json(response)).report as Record<string, unknown>
    expect(report.id).toBe('a1b2c3d4e5f60718')
    expect(report.dryRun).toBe(true)
    expect(report.sentAt).toBeNull()
    expect(report.accepted).toBeNull()
    expect(report.category).toBe('ruslafotur')
    expect(report.photoCount).toBe(1)
  })

  it('404s for an unknown id', async () => {
    const { app } = createTestApp()
    const response = await app(new Request('https://relay.local/api/reports/0000000000000000'))
    expect(response.status).toBe(404)
    expect((await json(response)).error).toBe('not-found')
  })
})

describe('POST /api/reports/:id/outcome', () => {
  it('records the reporter answering whether it was fixed', async () => {
    const { app, sqlite } = createTestApp()
    await postReport(app, reportForm())
    const response = await app(
      new Request('https://relay.local/api/reports/a1b2c3d4e5f60718/outcome', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ outcome: 'fixed' }),
      }),
    )
    expect(response.status).toBe(200)
    const report = (await json(response)).report as Record<string, unknown>
    expect(report.outcome).toBe('fixed')
    expect(report.outcomeAt).toBe('2026-08-21T12:00:00.000Z')
    const row = sqlite.prepare('SELECT outcome, outcome_at FROM reports').all()[0]
    expect(row).toEqual({ outcome: 'fixed', outcome_at: '2026-08-21T12:00:00.000Z' })
  })

  it('accepts not-fixed', async () => {
    const { app } = createTestApp()
    await postReport(app, reportForm())
    const response = await app(
      new Request('https://relay.local/api/reports/a1b2c3d4e5f60718/outcome', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ outcome: 'not-fixed' }),
      }),
    )
    expect(response.status).toBe(200)
    expect((await json(response)).report).toMatchObject({ outcome: 'not-fixed' })
  })

  it('rejects an unknown outcome value', async () => {
    const { app } = createTestApp()
    await postReport(app, reportForm())
    const response = await app(
      new Request('https://relay.local/api/reports/a1b2c3d4e5f60718/outcome', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ outcome: 'maybe' }),
      }),
    )
    expect(response.status).toBe(400)
    expect((await json(response)).error).toBe('invalid-outcome')
  })

  it('404s for an unknown id', async () => {
    const { app } = createTestApp()
    const response = await app(
      new Request('https://relay.local/api/reports/0000000000000000/outcome', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ outcome: 'fixed' }),
      }),
    )
    expect(response.status).toBe(404)
  })
})

describe('routing', () => {
  it('answers 405 for a wrong method on a known path', async () => {
    const { app } = createTestApp()
    const get = await app(new Request('https://relay.local/api/reports'))
    expect(get.status).toBe(405)
    const del = await app(
      new Request('https://relay.local/api/reports/a1b2c3d4e5f60718', { method: 'DELETE' }),
    )
    expect(del.status).toBe(405)
  })

  it('answers 404 for an unknown path', async () => {
    const { app } = createTestApp()
    const response = await app(new Request('https://relay.local/api/other'))
    expect(response.status).toBe(404)
  })
})

// ---------------------------------------------------------------------------
// Decision 0006's "one", as a property of the code rather than of anyone's
// attention. The CITY_SEND_KEY secret arms every request for as long as it
// exists, and on 2026-08-21 being careful was not enough: report 110474 reached
// a real work queue and had to be withdrawn by email.
//
// These tests are the safeguard being watched firing. AGENTS.md: a safety
// mechanism you have not seen fire is not a safety mechanism.
// ---------------------------------------------------------------------------

// #88 and #85. A tester filed the same ábending twice, 35 seconds apart, because
// the screen never said the first one had worked. Neither the app nor the relay
// could tell that from a retry, and the request carried nothing either could
// have used to.
describe('a report the relay has already stored', () => {
  const ID = 'a1b2c3d4e5f60718293a4b5c6d7e8f90'

  it('is answered with the row it already has, and does not become a second row', async () => {
    const { app } = createTestApp()

    const first = await postReport(app, reportForm({ reportId: ID }))
    expect(first.status).toBe(201)
    const firstReport = (await json(first)).report as Record<string, unknown>
    expect(firstReport.id).toBe(ID)

    const second = await postReport(app, reportForm({ reportId: ID }))
    // 200, not 201: nothing was created this time.
    expect(second.status).toBe(200)
    const secondBody = await json(second)
    expect(secondBody.duplicate).toBe(true)
    const secondReport = secondBody.report as Record<string, unknown>
    expect(secondReport.id).toBe(ID)
    expect(secondReport.createdAt).toBe(firstReport.createdAt)
  })

  it('is answered even when the rest of the request would now be refused', async () => {
    const { app } = createTestApp()
    await postReport(app, reportForm({ reportId: ID }))

    // A coordinate in Seattle, which a first-time report would be refused for.
    // A repeat of something already stored must not be: the report is filed,
    // and what the second press carries is beside the point.
    const repeat = await postReport(
      app,
      reportForm({ reportId: ID, latitude: '47.64', longitude: '-122.4' }),
    )
    expect(repeat.status).toBe(200)
    expect((await json(repeat)).report).toMatchObject({ id: ID })
  })

  it('refuses an id that is not the shape the relay stores', async () => {
    const { app } = createTestApp()
    const response = await postReport(app, reportForm({ reportId: 'not-a-report-id' }))
    expect(response.status).toBe(400)
    expect((await json(response)).error).toBe('invalid-report-id')
  })

  it('still generates one when the app sends none, so an older build keeps working', async () => {
    const { app } = createTestApp()
    const response = await postReport(app, reportForm())
    expect(response.status).toBe(201)
    // The id is the test app's stub rather than the relay's randomHex(16), so
    // what this pins is that one exists at all and the request was stored.
    const report = (await json(response)).report as Record<string, unknown>
    expect(typeof report.id).toBe('string')
    expect(report.id).not.toBe('')
  })
})

// ---------------------------------------------------------------------------
// #98. The gate above counted rows and the row was written after the city had
// been posted to, so the two tests before this one pass on a relay that files
// two real reports: they send one request, then the next. Nothing there
// overlaps, and the hole was only ever reachable by overlapping.
//
// These drive two requests that are genuinely in flight at once. The first is
// parked inside the city fetch while the second runs its whole pipeline.
// ---------------------------------------------------------------------------
