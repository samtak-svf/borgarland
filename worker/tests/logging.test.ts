// What the relay writes to Workers Logs, and what it must never write.
//
// The log line exists because a REFUSED report is never inserted: the
// jurisdiction check and every validation failure throw before the insert, so
// during a field test the most interesting outcome left no trace at all.
//
// The second half of these tests is the more important one. A log is a place
// personal data leaks into by accident, the privacy policy is still open (#5),
// and "we only log a bit of metadata" is the kind of claim that rots silently.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createTestApp, json, KOPAVOGUR_POINT, postReport, reportForm } from './helpers/fixtures'

const SECRET_DESCRIPTION = 'Sorpid vid husid mitt og simanumerid mitt er 5812345'
const SECRET_EMAIL = 'einhver@example.is'

let logged: string[]

beforeEach(() => {
  logged = []
  vi.spyOn(console, 'log').mockImplementation((line: unknown) => {
    logged.push(String(line))
  })
  vi.stubGlobal('fetch', () => {
    throw new Error('tests must never hit the real network')
  })
})

afterEach(() => {
  vi.restoreAllMocks()
  vi.unstubAllGlobals()
})

function lines(): Record<string, unknown>[] {
  return logged.map((l) => JSON.parse(l) as Record<string, unknown>)
}

describe('a recorded report is logged', () => {
  it('says what happened without saying what was written', async () => {
    const { app } = createTestApp()
    await postReport(app, reportForm({ description: SECRET_DESCRIPTION, email: SECRET_EMAIL }))

    const [event] = lines()
    expect(event.kind).toBe('report')
    expect(event.outcome).toBe('recorded')
    expect(event.dryRun).toBe(true)
    expect(event.category).toBe('ruslafotur')
    expect(event.photoCount).toBe(1)
    // The postcode is enough to tell a correct decision from a registry bug.
    expect(event.postalCode).toBe('101')
  })
})

describe('a refused report is logged, because nothing else records it', () => {
  it('logs the jurisdiction refusal that never reaches the database', async () => {
    const { app, sqlite } = createTestApp()
    const response = await postReport(app, reportForm(KOPAVOGUR_POINT))
    expect(response.status).toBe(400)

    // The whole reason this log line exists.
    const rows = sqlite.prepare('SELECT COUNT(*) AS n FROM reports').all()
    expect((rows[0] as { n: number }).n).toBe(0)

    const [event] = lines()
    expect(event.outcome).toBe('refused')
    expect(event.code).toBe('outside-reykjavik')
    expect(event.status).toBe(400)
    // Which municipality answered, so a wrong refusal is diagnosable.
    expect(event.svfnr).toBe(1000)
  })

  it('logs a validation refusal with the offending field', async () => {
    const { app } = createTestApp()
    await postReport(app, reportForm({ category: 'ekki-til' }))

    const [event] = lines()
    expect(event.outcome).toBe('refused')
    expect(event.code).toBe('unknown-category')
  })
})

describe('what a log line must never carry', () => {
  it('never logs the description, the email or the coordinate', async () => {
    const { app } = createTestApp()
    await postReport(app, reportForm({ description: SECRET_DESCRIPTION, email: SECRET_EMAIL }))
    // A refusal too: its error carries a nearest ADDRESS, which is a location.
    await postReport(app, reportForm({ ...KOPAVOGUR_POINT, description: SECRET_DESCRIPTION }))

    const all = logged.join('\n')
    expect(all).not.toContain(SECRET_DESCRIPTION)
    expect(all).not.toContain(SECRET_EMAIL)
    expect(all).not.toContain('5812345')
    // Coordinates, in the exact form the request carried them.
    expect(all).not.toContain('64.14658919')
    expect(all).not.toContain('-21.93279823')
    expect(all).not.toContain(KOPAVOGUR_POINT.latitude)
    // The street line the 400 response hands back to the client.
    expect(all).not.toContain('Hamraborg')
    expect(all).not.toContain('Laugavegur')
  })

  it('logs one line per request and nothing else', async () => {
    const { app } = createTestApp()
    await postReport(app, reportForm())
    expect(logged).toHaveLength(1)
    expect(() => JSON.parse(logged[0])).not.toThrow()
  })
})

describe('the health endpoint is not traffic', () => {
  it('does not log', async () => {
    const { app } = createTestApp()
    await json(await app(new Request('https://relay.local/api/health')))
    expect(logged).toHaveLength(0)
  })
})

// ---------------------------------------------------------------------------
// #140. A refused events batch used to be logged as `kind: 'report'`, because
// every handler throws into one router-wide catch and that catch named the
// kind itself.
//
// This is the failure AGENTS.md calls the dangerous half of the
// deploy-before-ship rule. One unknown event name refuses the WHOLE batch; the
// app treats 4xx as REJECTED and drops it without retrying; the report travels
// on a separate handler and succeeds. So the person filing sees success, the
// measurement is gone, and the log line is the only thing that could ever say
// so — filed, until now, under the wrong endpoint.
// ---------------------------------------------------------------------------

const EVENT_SESSION = 'a1b2c3d4e5f6071829304a5b6c7d8e9f'

function postEvents(app: (r: Request) => Promise<Response>, events: unknown[]) {
  return app(
    new Request('https://relay.local/api/events', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        session: EVENT_SESSION,
        platform: 'ios',
        appVersion: '0.1.0 (6)',
        events,
      }),
    }),
  )
}

describe('a refused batch is logged as the endpoint that refused it', () => {
  it('says events, not report', async () => {
    const { app } = createTestApp()
    const response = await postEvents(app, [
      { name: 'app-opened', atMs: 0 },
      { name: 'nothing-like-this', atMs: 1 },
    ])
    expect(response.status).toBe(400)

    const [event] = lines()
    expect(event.kind).toBe('events')
    expect(event.outcome).toBe('refused')
    expect(event.code).toBe('invalid-event-batch')
  })

  it('names the event the contract did not know, which is the whole diagnosis', async () => {
    const { app } = createTestApp()
    await postEvents(app, [{ name: 'nothing-like-this', atMs: 1 }])

    const [event] = lines()
    expect(event.name).toBe('nothing-like-this')
    expect(event.reason).toBe('unknown event name')
  })

  it('names the known event and the field when a field is the problem', async () => {
    const { app } = createTestApp()
    await postEvents(app, [{ name: 'app-opened', atMs: 0, smuggled: 'x' }])

    const [event] = lines()
    // `event` is matched against the allowlist before this throw is reachable,
    // so it carries no more than data/relay-events.json already publishes.
    expect(event.event).toBe('app-opened')
    expect(event.field).toBe('smuggled')
  })

  it('still logs a refused report as a report, which is what it always did', async () => {
    const { app } = createTestApp()
    await postReport(app, reportForm(KOPAVOGUR_POINT))
    expect(lines()[0].kind).toBe('report')
  })
})

describe('the one client-controlled string in a log line is filtered', () => {
  // `name` reaches a log only on the throw that says the name is UNKNOWN, so
  // by construction the allowlist did not match it: it is an arbitrary string
  // from the client. #140 reasoned the opposite way round, which is why this
  // is tested rather than argued.
  it('keeps a real event name intact', async () => {
    const { app } = createTestApp()
    await postEvents(app, [{ name: 'photo-captured-typo', atMs: 1 }])
    expect(lines()[0].name).toBe('photo-captured-typo')
  })

  it('a description cannot ride the name field into the logs', async () => {
    const { app } = createTestApp()
    await postEvents(app, [{ name: SECRET_DESCRIPTION, atMs: 1 }])

    const all = logged.join('\n')
    expect(all).not.toContain(SECRET_DESCRIPTION)
    expect(all).not.toContain('5812345')
    // Spaces and digits are gone, and the 40-character cap cuts it mid-word.
    // The shape survives well enough to debug with, which is the whole trade.
    expect(lines()[0].name).toBe('Sorpid.vid.husid.mitt.og.simanumerid.mit')
  })

  it('bounds the length, so no one field can flood a log line', async () => {
    const { app } = createTestApp()
    await postEvents(app, [{ name: 'a'.repeat(500), atMs: 1 }])
    expect(String(lines()[0].name)).toHaveLength(40)
  })

  it('a non-string name logs as null rather than as an object', async () => {
    const { app } = createTestApp()
    await postEvents(app, [{ name: { nested: 'x' }, atMs: 1 }])
    expect(lines()[0].name).toBeNull()
  })
})
