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
  postReport,
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

describe('live sending requires the deliberate secret', () => {
  it('a weak or malformed CITY_SEND_KEY keeps the relay in dry run', async () => {
    // A secret that was set but does not pass the shape check must fail closed.
    const { app, env } = createTestApp()
    env.CITY_SEND_KEY = 'false'
    const response = await postReport(app, reportForm())
    expect(response.status).toBe(201)
    expect((await json(response)).report).toMatchObject({ dryRun: true })
  })

  it('with a strong secret it POSTs to the city exactly once and records the outcome', async () => {
    // Object capture: property mutation is visible to TS, where a closure
    // reassigned `let` would narrow to never (TS 6 control-flow analysis).
    const captured: { calls: number; url: string; fd: FormData | null } = {
      calls: 0,
      url: '',
      fd: null,
    }
    const { app, sqlite } = createTestApp({
      live: true,
      cityFetch: async (input, init) => {
        captured.calls += 1
        const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url
        captured.url = url
        captured.fd = await new Request(url, init).formData()
        return new Response(SUCCESS_200, { status: 200 })
      },
    })

    const response = await postReport(app, reportForm())
    expect(response.status).toBe(201)
    const report = (await json(response)).report as Record<string, unknown>
    expect(report.dryRun).toBe(false)
    expect(report.accepted).toBe(true)
    expect(report.cityReference).toBe('110999')
    expect(report.sentAt).toBe('2026-08-21T12:00:00.000Z')

    expect(captured.calls).toBe(1)
    expect(captured.url).toContain('/abendingar/senda-abendingu/ruslafotur')
    expect(captured.fd?.get('type')).toBe('specific')
    expect(captured.fd?.get('category')).toBe('Ruslafötur')
    expect((captured.fd?.getAll('files') ?? []).length).toBe(1)

    const row = sqlite.prepare('SELECT * FROM reports').all()[0] as Record<string, unknown>
    expect(row.dry_run).toBe(0)
    expect(row.city_status).toBe(200)
    expect(row.city_reference).toBe('110999')
    expect(row.sent_at).not.toBeNull()
  })
})

describe('the city 400 ambiguity is resolved by the body, not the status', () => {
  it('a validation 400 is recorded as rejection=validation', async () => {
    const { app } = createTestApp({
      live: true,
      cityFetch: async () => new Response(VALIDATION_400, { status: 400 }),
    })
    const response = await postReport(app, reportForm())
    expect(response.status).toBe(502)
    const body = await json(response)
    expect(body.error).toBe('city-rejected')
    const report = body.report as Record<string, unknown>
    expect(report.rejection).toBe('validation')
    expect(report.cityStatus).toBe(400)
    expect(report.accepted).toBe(false)
  })

  it('an unknown-route 400 is recorded as rejection=route', async () => {
    const { app } = createTestApp({
      live: true,
      cityFetch: async () => new Response(ROUTE_400, { status: 400 }),
    })
    const response = await postReport(app, reportForm())
    expect(response.status).toBe(502)
    expect((await json(response)).report).toMatchObject({ rejection: 'route', cityStatus: 400 })
  })

  it('a 500 is recorded as rejection=error', async () => {
    const { app } = createTestApp({
      live: true,
      cityFetch: async () => new Response('boom', { status: 500 }),
    })
    const response = await postReport(app, reportForm())
    expect(response.status).toBe(502)
    expect((await json(response)).report).toMatchObject({ rejection: 'error', cityStatus: 500 })
  })

  it('a network failure is recorded as rejection=error with no response status', async () => {
    const { app, sqlite } = createTestApp({
      live: true,
      cityFetch: async () => {
        throw new TypeError('fetch failed')
      },
    })
    const response = await postReport(app, reportForm())
    expect(response.status).toBe(502)
    const body = await json(response)
    expect(body.error).toBe('city-unreachable')
    expect(body.report).toMatchObject({ rejection: 'error', cityStatus: null, accepted: null })
    const row = sqlite.prepare('SELECT rejection, sent_at, dry_run FROM reports').all()[0]
    expect(row).toEqual({ rejection: 'error', sent_at: null, dry_run: 0 })
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

describe('the relay files one real report, ever', () => {
  /** Rows the relay believes it has actually sent. */
  function liveRows(sqlite: TestApp['sqlite']): number {
    const rows = sqlite.prepare('SELECT COUNT(*) AS n FROM reports WHERE dry_run = 0').all()
    return Number((rows[0] as { n: number }).n)
  }

  it('sends the first one, because that is the whole point', async () => {
    const calls: string[] = []
    const { app, sqlite } = createTestApp({
      live: true,
      cityFetch: async (input) => {
        calls.push(String(input))
        return new Response(donePage('110999'), { status: 200 })
      },
    })

    const response = await postReport(app, reportForm())
    expect(response.status).toBe(201)
    expect(calls).toHaveLength(1)

    const report = (await json(response)).report as Record<string, unknown>
    expect(report.dryRun).toBe(false)
    expect(report.cityReference).toBe('110999')
    expect(liveRows(sqlite)).toBe(1)
  })

  it('refuses the second, and does not call the city at all', async () => {
    let called = 0
    const { app, sqlite } = createTestApp({
      live: true,
      cityFetch: async () => {
        called += 1
        return new Response(donePage('110999'), { status: 200 })
      },
    })

    expect((await postReport(app, reportForm())).status).toBe(201)
    expect(called).toBe(1)

    const second = await postReport(app, reportForm())
    expect(second.status).toBe(409)
    expect((await json(second)).error).toBe('live-send-already-used')

    // The city was never asked, and nothing was recorded for an attempt that
    // did not happen.
    expect(called).toBe(1)
    expect(liveRows(sqlite)).toBe(1)
  })

  it('does not count dry-run rows, so earlier testing does not consume the one', async () => {
    // The live relay already holds several dry-run rows from the deploy checks.
    // If those counted, the one real submission could never be made at all.
    const { app, sqlite } = createTestApp({ live: false, uniqueIds: true })
    expect((await postReport(app, reportForm())).status).toBe(201)
    expect((await postReport(app, reportForm())).status).toBe(201)
    expect(liveRows(sqlite)).toBe(0)

    const live = createTestApp({
      live: true,
      cityFetch: async () => new Response(donePage('110999'), { status: 200 })
    })
    expect((await postReport(live.app, reportForm())).status).toBe(201)
    expect(liveRows(live.sqlite)).toBe(1)
    expect(sqlite).not.toBe(live.sqlite)
  })

  it('leaves dry run completely unaffected', async () => {
    // The gate is on the live path only. A relay with no secret must keep
    // accepting reports forever, which is its normal state.
    const { app, sqlite } = createTestApp({ uniqueIds: true })
    for (let i = 0; i < 3; i++) {
      expect((await postReport(app, reportForm())).status).toBe(201)
    }
    expect(liveRows(sqlite)).toBe(0)
  })
})
