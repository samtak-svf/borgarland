// The production path for the registry: D1 addresses table → in-memory index.
// This proves the actual SQL the Worker runs, against a real SQLite.

import { beforeEach, describe, expect, it } from 'vitest'
import { DatabaseSync } from 'node:sqlite'
import { FakeD1 } from './helpers/fake-d1'
import { MIGRATION_SQL } from './helpers/fixtures'
import { RegistryNotLoadedError, loadRegistry, resetRegistryCache } from '../src/registry-loader'

function seededDb(): DatabaseSync {
  const sqlite = new DatabaseSync(':memory:')
  sqlite.exec(MIGRATION_SQL)
  sqlite.exec(
    `INSERT INTO addresses (svfnr, street_nf, house_number, house_letter, postal_code, lat, lng) VALUES
     (0, 'Laugavegur', 1, NULL, '101', 64.14658919, -21.93279823),
     (0, 'Borgartún', 12, NULL, '105', 64.14394, -21.9122),
     (1000, 'Hamraborg', 3, NULL, '200', 64.1109, -21.901)`,
  )
  return sqlite
}

beforeEach(() => {
  resetRegistryCache()
})

describe('loadRegistry', () => {
  it('loads seeded rows and answers the jurisdiction question', async () => {
    const db = new FakeD1(seededDb()) as unknown as D1Database
    const registry = await loadRegistry(db)
    expect(registry.size).toBe(3)
    expect(registry.nearest(64.14658919, -21.93279823)?.svfnr).toBe(0)
    expect(registry.nearest(64.1109, -21.901)?.svfnr).toBe(1000)
  })

  it('caches the registry per isolate', async () => {
    const db = new FakeD1(seededDb()) as unknown as D1Database
    const first = await loadRegistry(db)
    const second = await loadRegistry(db)
    expect(second).toBe(first)
  })

  it('fails closed on an empty table', async () => {
    const sqlite = new DatabaseSync(':memory:')
    sqlite.exec(MIGRATION_SQL)
    const db = new FakeD1(sqlite) as unknown as D1Database
    await expect(loadRegistry(db)).rejects.toBeInstanceOf(RegistryNotLoadedError)
  })
})
