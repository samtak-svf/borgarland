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
