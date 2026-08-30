// The one real submission, as an operator act (#181).
//
// These tests inherit the safety properties that used to live in relay.test.ts,
// where a report could reach the city by arriving. That path is gone: a report
// is always stored as a dry run, and the city is posted to only by
// POST /api/reports/:id/promote, which needs a credential no app holds.
//
// The first describe below is the one that matters most. Everything else here
// pins the promote path; that one pins the absence of any other path.

import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest'
import {
  createTestApp,
  getPhoto,
  json,
  postReport,
  promoteReport,
  reportForm,
  TEST_LIVE_KEY,
} from './helpers/fixtures'
import type { TestApp } from './helpers/fixtures'

const SUCCESS_200 =
  '<html><body><a href="/abendingar/senda-abendingu/ruslafotur/done/110999">done</a></body></html>'

function donePage(reference: string): string {
  return `<html><body><a href="/abendingar/senda-abendingu/ruslafotur/done/${reference}">done</a></body></html>`
}

function liveRows(sqlite: TestApp['sqlite']): number {
  const rows = sqlite.prepare('SELECT COUNT(*) AS n FROM reports WHERE dry_run = 0').all()
  return Number((rows[0] as { n: number }).n)
}

/** File a report and hand back its id, which is what a promote needs. */
async function file(app: TestApp['app'], fd?: FormData): Promise<string> {
  const response = await postReport(app, fd ?? reportForm())
  expect(response.status).toBe(201)
  const report = (await json(response)).report as Record<string, unknown>
  return report.id as string
}

beforeEach(() => {
  vi.stubGlobal('fetch', () => {
    throw new Error('tests must never hit the real network')
  })
})

afterEach(() => {
  vi.unstubAllGlobals()
})

// The whole of #181 in one block: arriving cannot send, however the relay is
// configured. Before this change an armed relay POSTed the first report that
// reached it, whoever filed it.
describe('a report cannot reach the city by arriving', () => {
  it('is a dry run even with both halves of the gate armed', async () => {
    // No cityFetch: the fixture throws on an unexpected city call, so this
    // asserts twice — once on the body, once by not blowing up.
    const { app, sqlite } = createTestApp({ live: true })

    const response = await postReport(app, reportForm())
    expect(response.status).toBe(201)
    expect((await json(response)).report).toMatchObject({ dryRun: true })
    expect(liveRows(sqlite)).toBe(0)
  })

  it('is a dry run for every reporter, so an armed relay never answers 409 to a walk', async () => {
    // The failure #178 was filed about: an armed relay with the one already
    // spent used to refuse everybody. Now the gate is not on this path at all.
    const { app, sqlite, env } = createTestApp({
      live: true,
      uniqueIds: true,
      cityFetch: async () => new Response(donePage('110999'), { status: 200 }),
    })

    const first = await file(app)
    expect((await promoteReport(app, first)).status).toBe(200)
    expect(liveRows(sqlite)).toBe(1)
    expect(env.CITY_SEND_KEY).toBe(TEST_LIVE_KEY)

    // Somebody else walks, after the one is spent, with the relay still armed.
    const second = await postReport(app, reportForm())
    expect(second.status).toBe(201)
    expect((await json(second)).report).toMatchObject({ dryRun: true })
  })
})

describe('promote is the operator, or nobody', () => {
  it('refuses a request with no credential', async () => {
    const { app } = createTestApp({ live: true })
    const id = await file(app)
    const response = await promoteReport(app, id, { key: null })
    expect(response.status).toBe(401)
    expect((await json(response)).error).toBe('not-the-operator')
  })

  it('refuses a wrong credential of the same length', async () => {
    // Same length on purpose: a compare that returns early on the first
    // differing byte would still pass a length check.
    const { app } = createTestApp({ live: true })
    const id = await file(app)
    const wrong = TEST_LIVE_KEY.slice(0, -1) + (TEST_LIVE_KEY.endsWith('a') ? 'b' : 'a')
    expect(wrong).toHaveLength(TEST_LIVE_KEY.length)
    expect((await promoteReport(app, id, { key: wrong })).status).toBe(401)
  })

  it('refuses even the right credential while the switch is off', async () => {
    // Both halves, as before. Leaving the secret in place between occasions is
    // not an armed relay.
    const { app } = createTestApp({ citySendKey: TEST_LIVE_KEY })
    const id = await file(app)
    const response = await promoteReport(app, id)
    expect(response.status).toBe(409)
    expect((await json(response)).error).toBe('live-send-not-armed')
  })

  it('refuses a promote with no address, because the city could not answer it', async () => {
    const { app } = createTestApp({ live: true })
    const id = await file(app)
    const response = await promoteReport(app, id, { email: null as unknown as string })
    expect(response.status).toBe(400)
    expect((await json(response)).error).toBe('email-required')
  })

  it('answers 404 for a report it has never stored', async () => {
    const { app } = createTestApp({ live: true })
    const response = await promoteReport(app, 'ffffffffffffffffffffffffffffffff')
    expect(response.status).toBe(404)
  })
})

describe('promote files one real report, ever', () => {
  it('sends it once and records what the city said', async () => {
    const calls: string[] = []
    const { app, sqlite } = createTestApp({
      live: true,
      cityFetch: async (input) => {
        calls.push(String(input))
        return new Response(donePage('110999'), { status: 200 })
      },
    })

    const id = await file(app)
    const response = await promoteReport(app, id)
    expect(response.status).toBe(200)
    expect(calls).toHaveLength(1)

    const report = (await json(response)).report as Record<string, unknown>
    expect(report.dryRun).toBe(false)
    expect(report.cityReference).toBe('110999')
    expect(report.sentAt).not.toBeNull()
    expect(liveRows(sqlite)).toBe(1)
  })

  it('carries the address supplied at promote time, and still stores none', async () => {
    // Object capture, the idiom relay.test.ts already uses: property mutation
    // is visible to TS, where a closure reassigning a `let` narrows it to never.
    const captured: { form: FormData | null } = { form: null }
    const { app, sqlite } = createTestApp({
      live: true,
      cityFetch: async (input, init) => {
        captured.form = await new Request(String(input), init).formData()
        return new Response(SUCCESS_200, { status: 200 })
      },
    })

    const id = await file(app)
    expect((await promoteReport(app, id, { email: 'nafn@daemi.is' })).status).toBe(200)
    expect(captured.form?.get('email')).toBe('nafn@daemi.is')

    // The row has nowhere to put one — migration 0004, decision 0015.
    const columns = sqlite.prepare("SELECT name FROM pragma_table_info('reports')").all()
    expect(columns.map((c) => (c as { name: string }).name)).not.toContain('email')
  })

  it('refuses a second report, and does not call the city at all', async () => {
    let called = 0
    const { app, sqlite } = createTestApp({
      live: true,
      uniqueIds: true,
      cityFetch: async () => {
        called += 1
        return new Response(donePage('110999'), { status: 200 })
      },
    })

    const first = await file(app)
    const second = await file(app)
    expect((await promoteReport(app, first)).status).toBe(200)
    expect(called).toBe(1)

    const refused = await promoteReport(app, second)
    expect(refused.status).toBe(409)
    expect((await json(refused)).error).toBe('live-send-already-used')
    expect(called).toBe(1)
    expect(liveRows(sqlite)).toBe(1)
  })

  it('answers a repeat promote of the same report with its row, not a second send', async () => {
    // The operator's finger slipping is not a second submission being
    // attempted, and must not be answered as though it were.
    let called = 0
    const { app } = createTestApp({
      live: true,
      cityFetch: async () => {
        called += 1
        return new Response(donePage('110999'), { status: 200 })
      },
    })

    const id = await file(app)
    expect((await promoteReport(app, id)).status).toBe(200)

    const again = await promoteReport(app, id)
    expect(again.status).toBe(200)
    const body = await json(again)
    expect(body.alreadyLive).toBe(true)
    expect((body.report as Record<string, unknown>).cityReference).toBe('110999')
    expect(called).toBe(1)
  })

  it('does not count dry-run rows, so testing does not consume the one', async () => {
    const { app, sqlite } = createTestApp({
      live: true,
      uniqueIds: true,
      cityFetch: async () => new Response(donePage('110999'), { status: 200 }),
    })

    await file(app)
    await file(app)
    const third = await file(app)
    expect(liveRows(sqlite)).toBe(0)

    expect((await promoteReport(app, third)).status).toBe(200)
    expect(liveRows(sqlite)).toBe(1)
  })
})

describe('two promotes in flight at once', () => {
  it('lets exactly one of two different reports reach the city', async () => {
    let called = 0
    // Same capture idiom: the executor assigns from inside a closure.
    const gate: { release: (() => void) | null } = { release: null }
    const held = new Promise<void>((resolve) => {
      gate.release = resolve
    })

    const { app, sqlite } = createTestApp({
      live: true,
      uniqueIds: true,
      cityFetch: async () => {
        called += 1
        await held
        return new Response(donePage('110999'), { status: 200 })
      },
    })

    const a = await file(app)
    const b = await file(app)

    const both = Promise.all([promoteReport(app, a), promoteReport(app, b)])
    gate.release?.()
    const [first, second] = await both

    const statuses = [first.status, second.status].sort()
    expect(statuses).toEqual([200, 409])
    expect(called).toBe(1)
    expect(liveRows(sqlite)).toBe(1)
  })

  it('flips the row before the city is asked, which is the whole ordering', async () => {
    // The reorder #98 was about, carried over to the UPDATE: the row counts
    // against the gate from the moment the city could possibly have been
    // reached, never after.
    let liveAtCallTime = -1
    const { app, sqlite } = createTestApp({
      live: true,
      cityFetch: async () => {
        liveAtCallTime = liveRows(sqlite)
        return new Response(donePage('110999'), { status: 200 })
      },
    })

    const id = await file(app)
    expect((await promoteReport(app, id)).status).toBe(200)
    expect(liveAtCallTime).toBe(1)
  })

  it('keeps the one spent when the city cannot be reached, and says so', async () => {
    // A throw cannot distinguish a request that never left from one whose
    // answer was lost, so the one stays spent deliberately.
    const { app, sqlite } = createTestApp({
      live: true,
      uniqueIds: true,
      cityFetch: async () => {
        throw new Error('connection reset')
      },
    })

    const id = await file(app)
    const response = await promoteReport(app, id)
    expect(response.status).toBe(502)
    const body = await json(response)
    expect(body.error).toBe('city-unreachable')
    expect((body.report as Record<string, unknown>).rejection).toBe('error')
    expect((body.report as Record<string, unknown>).sentAt).toBeNull()
    expect(liveRows(sqlite)).toBe(1)

    const another = await file(app)
    expect((await promoteReport(app, another)).status).toBe(409)
  })
})

describe('the photographs a promote needs', () => {
  it('are readable by the operator, so a report can be reviewed before it is filed', async () => {
    const { app } = createTestApp({ live: true })
    const id = await file(app)

    const response = await getPhoto(app, id, 0)
    expect(response.status).toBe(200)
    expect(response.headers.get('content-type')).toBe('image/jpeg')
    expect((await response.arrayBuffer()).byteLength).toBeGreaterThan(0)
  })

  it('are not readable by anyone else — they are other people’s', async () => {
    const { app } = createTestApp({ live: true })
    const id = await file(app)
    expect((await getPhoto(app, id, 0, null)).status).toBe(401)
  })

  it('answer 404 for an index that was never stored', async () => {
    const { app } = createTestApp({ live: true })
    const id = await file(app)
    expect((await getPhoto(app, id, 7)).status).toBe(404)
  })

  it('refuse the promote once the bucket has expired them, rather than filing without evidence', async () => {
    const { app, env } = createTestApp({ live: true })
    const id = await file(app)

    // What the 30-day lifecycle rule does, driven here.
    ;(env.PHOTOS as unknown as { forget: (key: string) => void }).forget(`${id}/0`)

    const response = await promoteReport(app, id)
    expect(response.status).toBe(410)
    expect((await json(response)).error).toBe('photo-expired')
  })
})
