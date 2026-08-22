// POST /api/events, and the allowlist that is the privacy boundary.
//
// The endpoint exists because the relay could not see the half of a field test
// that matters: everything the app did before it posted a report, including the
// reports it never got to post.
//
// The second describe block is the one that must never be deleted. A telemetry
// channel is where personal data ends up by accident, the privacy policy is
// still open (#5), and "it only carries numbers" is a claim that rots unless
// something checks it. data/relay-events.json names no free-text field, and
// these tests are what hold that true.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createTestApp, json } from './helpers/fixtures'
import type { TestApp } from './helpers/fixtures'

const SESSION = 'a1b2c3d4e5f6071829304a5b6c7d8e9f'

function batch(overrides: Record<string, unknown> = {}) {
  return {
    session: SESSION,
    platform: 'ios',
    appVersion: '0.1.0 (3)',
    events: [{ name: 'app-opened', atMs: 0 }],
    ...overrides,
  }
}

function post(app: TestApp['app'], body: unknown) {
  return app(
    new Request('https://relay.local/api/events', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: typeof body === 'string' ? body : JSON.stringify(body),
    }),
  )
}

function storedFields(sqlite: TestApp['sqlite']): Record<string, unknown>[] {
  return sqlite
    .prepare('SELECT name, at_ms, fields FROM client_events ORDER BY id')
    .all() as Record<string, unknown>[]
}

beforeEach(() => {
  vi.spyOn(console, 'log').mockImplementation(() => {})
  vi.stubGlobal('fetch', () => {
    throw new Error('tests must never hit the real network')
  })
})

afterEach(() => {
  vi.restoreAllMocks()
  vi.unstubAllGlobals()
})

describe('a timeline is recorded', () => {
  it('accepts a batch and stores every event', async () => {
    const { app, sqlite } = createTestApp()
    const response = await post(
      app,
      batch({
        events: [
          { name: 'app-opened', atMs: 0 },
          { name: 'camera-permission', atMs: 900, granted: true },
          { name: 'location-resolved', atMs: 4200, elapsedMs: 3300, source: 'device', accuracyM: 12 },
          { name: 'category-chosen', atMs: 9100, elapsedMs: 4900, slug: 'ruslafotur' },
          { name: 'description-length', atMs: 21000, length: 47 },
          { name: 'send-result', atMs: 23000, elapsedMs: 2000, status: 201, ok: true },
        ],
      }),
    )

    expect(response.status).toBe(202)
    expect((await json(response)).stored).toBe(6)

    const rows = storedFields(sqlite)
    expect(rows).toHaveLength(6)
    expect(rows[2].name).toBe('location-resolved')
    // The question the field test is actually asking: how long, how accurate.
    expect(JSON.parse(rows[2].fields as string)).toEqual({
      elapsedMs: 3300,
      source: 'device',
      accuracyM: 12,
    })
  })

  it('records the send that never reached us, which is the whole point', async () => {
    const { app, sqlite } = createTestApp()
    await post(
      app,
      batch({
        events: [{ name: 'send-failed', atMs: 30000, elapsedMs: 10000, reason: 'connection' }],
      }),
    )
    const rows = storedFields(sqlite)
    expect(JSON.parse(rows[0].fields as string)).toEqual({
      elapsedMs: 10000,
      reason: 'connection',
    })
  })

  it('records an abandoned attempt, which leaves no report at all', async () => {
    const { app, sqlite } = createTestApp()
    await post(
      app,
      batch({ events: [{ name: 'screen-left', atMs: 5000, screen: 'details', completed: false }] }),
    )
    expect(storedFields(sqlite)).toHaveLength(1)
  })
})

describe('what this channel must be incapable of carrying', () => {
  it('refuses a field the contract does not name', async () => {
    const { app, sqlite } = createTestApp()
    const response = await post(
      app,
      batch({
        events: [
          { name: 'description-length', atMs: 1, length: 12, text: 'Full ruslafata vid stiginn' },
        ],
      }),
    )
    expect(response.status).toBe(400)
    expect((await json(response)).error).toBe('invalid-event-batch')
    // Refused whole. Not stored with the offending field quietly dropped.
    expect(storedFields(sqlite)).toHaveLength(0)
  })

  it('refuses a coordinate however it is dressed up', async () => {
    const { app } = createTestApp()
    for (const event of [
      {
        name: 'location-resolved',
        atMs: 1,
        elapsedMs: 1,
        source: 'device',
        accuracyM: 12,
        lat: 64.14658919,
      },
      { name: 'location-resolved', atMs: 1, elapsedMs: 1, source: 'device', accuracyM: '64.146' },
      { name: 'app-opened', atMs: 0, latitude: 64.14658919 },
    ]) {
      const response = await post(app, batch({ events: [event] }))
      expect(response.status).toBe(400)
    }
  })

  it('refuses an unknown event name rather than storing a free-form one', async () => {
    const { app, sqlite } = createTestApp()
    const response = await post(app, batch({ events: [{ name: 'user-said', atMs: 1 }] }))
    expect(response.status).toBe(400)
    expect(storedFields(sqlite)).toHaveLength(0)
  })

  it('refuses an envelope field the contract does not name', async () => {
    const { app } = createTestApp()
    const response = await post(app, batch({ email: 'einhver@example.is' }))
    expect(response.status).toBe(400)
  })

  it('will not take a description smuggled through appVersion', async () => {
    const { app } = createTestApp()
    const response = await post(
      app,
      batch({ appVersion: 'Full ruslafata vid stiginn, simi 5812345!' }),
    )
    expect(response.status).toBe(400)
  })

  it('refuses a slug that is not a real category', async () => {
    const { app } = createTestApp()
    const response = await post(
      app,
      batch({ events: [{ name: 'category-chosen', atMs: 1, elapsedMs: 1, slug: 'not-a-category' }] }),
    )
    expect(response.status).toBe(400)
  })

  it('stores only the fields the contract names, never the raw event object', async () => {
    const { app, sqlite } = createTestApp()
    await post(app, batch({ events: [{ name: 'camera-permission', atMs: 5, granted: false }] }))
    const stored = JSON.parse(storedFields(sqlite)[0].fields as string)
    expect(stored).toEqual({ granted: false })
    expect(stored).not.toHaveProperty('name')
    expect(stored).not.toHaveProperty('atMs')
  })
})

describe('the envelope', () => {
  it('refuses a session that is not a fresh random one', async () => {
    const { app } = createTestApp()
    for (const session of ['', 'abc', SESSION.toUpperCase(), 'device-imei-35209900176148']) {
      expect((await post(app, batch({ session }))).status).toBe(400)
    }
  })

  it('refuses an unknown platform', async () => {
    const { app } = createTestApp()
    expect((await post(app, batch({ platform: 'web' }))).status).toBe(400)
  })

  it('refuses an oversized batch rather than truncating it', async () => {
    const { app, sqlite } = createTestApp()
    const events = Array.from({ length: 101 }, (_, i) => ({ name: 'app-opened', atMs: i }))
    const response = await post(app, batch({ events }))
    expect(response.status).toBe(400)
    // A silently shortened timeline is a timeline with a hole nothing reports.
    expect(storedFields(sqlite)).toHaveLength(0)
  })

  it('refuses an empty batch and a body that is not JSON', async () => {
    const { app } = createTestApp()
    expect((await post(app, batch({ events: [] }))).status).toBe(400)
    expect((await post(app, 'not json')).status).toBe(400)
  })

  it('refuses a coerced or nonsensical atMs', async () => {
    const { app } = createTestApp()
    for (const atMs of ['0', 1.5, -1, Number.NaN, 86400001]) {
      const response = await post(app, batch({ events: [{ name: 'app-opened', atMs }] }))
      expect(response.status).toBe(400)
    }
  })

  it('refuses a missing required field instead of storing a partial event', async () => {
    const { app } = createTestApp()
    const response = await post(app, batch({ events: [{ name: 'camera-permission', atMs: 1 }] }))
    expect(response.status).toBe(400)
  })
})

describe('the route', () => {
  it('refuses a method it does not serve', async () => {
    const { app } = createTestApp()
    expect((await app(new Request('https://relay.local/api/events'))).status).toBe(405)
  })
})
