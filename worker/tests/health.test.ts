// GET /api/health — the operational readout.
//
// This endpoint exists for one reason, recorded in decision 0009: the registry
// refresh is unowned, and a stale registry degrades the jurisdiction check
// silently instead of failing it. Every test here is about making a state that
// used to be invisible readable from outside.

import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest'
import { createTestApp, json } from './helpers/fixtures'
import type { TestApp } from './helpers/fixtures'

// Ten days before the fixtures' fixed clock (2026-08-21T12:00:00.000Z).
const TEN_DAYS_EARLIER = '2026-08-11T12:00:00.000Z'

function getHealth(app: TestApp['app']) {
  return app(new Request('https://relay.local/api/health'))
}

function seedAddresses(sqlite: TestApp['sqlite'], count: number) {
  for (let i = 0; i < count; i++) {
    sqlite
      .prepare(
        'INSERT INTO addresses (svfnr, street_nf, house_number, house_letter, postal_code, lat, lng)' +
          ' VALUES (0, ?, ?, NULL, ?, ?, ?)',
      )
      .run('Laugavegur', i + 1, '101', 64.1465 + i / 10000, -21.9327)
  }
}

function seedMeta(sqlite: TestApp['sqlite'], snapshotAt: string, rowCount: number) {
  sqlite
    .prepare(
      'INSERT OR REPLACE INTO registry_meta (id, snapshot_at, row_count, source) VALUES (1, ?, ?, ?)',
    )
    .run(snapshotAt, rowCount, 'Staðfangaskrá (HMS / Þjóðskrá Íslands, CC-BY 4.0)')
}

beforeEach(() => {
  vi.stubGlobal('fetch', () => {
    throw new Error('tests must never hit the real network')
  })
})

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('an unseeded registry is unhealthy, not quietly fine', () => {
  it('answers 503 and says which state it is in', async () => {
    const { app } = createTestApp()
    const response = await getHealth(app)

    // The same refusal the report path gives, for the same reason: with no
    // addresses the relay refuses every submission.
    expect(response.status).toBe(503)

    const body = await json(response)
    expect(body.status).toBe('registry-not-loaded')

    const registry = body.registry as Record<string, unknown>
    expect(registry.rows).toBe(0)
    expect(registry.snapshotAt).toBeNull()
    expect(registry.ageDays).toBeNull()
    expect(registry.seededRows).toBeNull()
  })
})

describe('a seeded registry reports its age', () => {
  it('answers 200 with the row count and whole days since the snapshot', async () => {
    const { app, sqlite } = createTestApp()
    seedAddresses(sqlite, 3)
    seedMeta(sqlite, TEN_DAYS_EARLIER, 3)

    const response = await getHealth(app)
    expect(response.status).toBe(200)

    const body = await json(response)
    expect(body.status).toBe('ok')

    const registry = body.registry as Record<string, unknown>
    expect(registry.rows).toBe(3)
    expect(registry.snapshotAt).toBe(TEN_DAYS_EARLIER)
    expect(registry.ageDays).toBe(10)
    expect(registry.seededRows).toBe(3)
  })

  it('says the age is unknown rather than inventing one when the seed predates the meta table', async () => {
    const { app, sqlite } = createTestApp()
    seedAddresses(sqlite, 2)

    const body = await json(await getHealth(app))
    expect(body.status).toBe('ok')

    const registry = body.registry as Record<string, unknown>
    expect(registry.rows).toBe(2)
    expect(registry.snapshotAt).toBeNull()
    expect(registry.ageDays).toBeNull()
  })
})

describe('a partially applied seed is visible', () => {
  it('reports the live count and the seed’s own claim separately', async () => {
    const { app, sqlite } = createTestApp()
    // What an 8.8 MB seed interrupted over the network leaves behind: rows
    // present, but not the rows the seed said it wrote.
    seedAddresses(sqlite, 4)
    seedMeta(sqlite, TEN_DAYS_EARLIER, 139_347)

    const body = await json(await getHealth(app))
    const registry = body.registry as Record<string, unknown>

    expect(registry.rows).toBe(4)
    expect(registry.seededRows).toBe(139_347)
    // The relay cannot tell whether 4 rows is right, so it does not claim to —
    // it reports both numbers and leaves the discrepancy legible.
    expect(registry.rows).not.toBe(registry.seededRows)
  })
})

describe('the dry-run gate is readable', () => {
  it('reports dry run by default', async () => {
    const { app, sqlite } = createTestApp()
    seedAddresses(sqlite, 1)
    const body = await json(await getHealth(app))
    expect(body.dryRun).toBe(true)
  })

  it('reports live once the deliberate secret is in place', async () => {
    const { app, sqlite } = createTestApp({ live: true })
    seedAddresses(sqlite, 1)
    const body = await json(await getHealth(app))
    expect(body.dryRun).toBe(false)
  })

  it('never echoes the secret itself', async () => {
    const { app, sqlite } = createTestApp({ live: true })
    seedAddresses(sqlite, 1)
    const text = await (await getHealth(app)).text()
    expect(text).not.toContain('test-live-key')
  })
})

describe('the route', () => {
  it('refuses a method it does not serve', async () => {
    const { app } = createTestApp()
    const response = await app(new Request('https://relay.local/api/health', { method: 'POST' }))
    expect(response.status).toBe(405)
  })
})
