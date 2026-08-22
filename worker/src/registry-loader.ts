// Loads the address registry from the D1 `addresses` table into an in-memory
// Registry. The table is seeded by scripts/refresh-registry.mjs (which generates
// data/addresses.seed.sql, applied with `wrangler d1 execute --file`), or by a
// scheduled refresh.
//
// The registry is loaded once per isolate and cached in module state: a request
// that needs the jurisdiction check pays the SELECT + index build once, and the
// next request on the same isolate reuses it. A new deploy (new isolate) picks
// up refreshed rows.
//
// An empty table is a fail-closed error, not a silent pass: with no addresses
// the relay cannot establish jurisdiction, so every report is refused with 503
// rather than filed. The alternative — filing without knowing whose queue it
// lands in — is exactly what the jurisdiction check exists to prevent.

import { Registry } from './registry'
import type { AddressPoint } from './registry'

export class RegistryNotLoadedError extends Error {
  constructor() {
    super('the address registry has not been seeded; run scripts/refresh-registry.mjs and apply data/addresses.seed.sql')
  }
}

interface AddressRow {
  svfnr: number | null
  street_nf: string
  house_number: number | null
  house_letter: string | null
  postal_code: string
  lat: number
  lng: number
}

export function rowToAddressPoint(row: AddressRow): AddressPoint {
  return {
    svfnr: row.svfnr,
    streetNf: row.street_nf,
    houseNumber: row.house_number,
    houseLetter: row.house_letter,
    postalCode: row.postal_code,
    lat: row.lat,
    lng: row.lng,
  }
}

let cache: Registry | null = null

export function resetRegistryCache(): void {
  cache = null
}

export async function loadRegistry(db: D1Database): Promise<Registry> {
  if (cache !== null) return cache
  const result = await db
    .prepare(
      'SELECT svfnr, street_nf, house_number, house_letter, postal_code, lat, lng FROM addresses',
    )
    .all()
  const rows = (result.results ?? []) as unknown as AddressRow[]
  if (rows.length === 0) {
    throw new RegistryNotLoadedError()
  }
  cache = new Registry(rows.map(rowToAddressPoint))
  return cache
}

// ---------------------------------------------------------------------------
// The registry's age, for GET /api/health.
//
// Decision 0009 accepted keeping the registry here and named the cost: the
// refresh chore is unowned, and a stale registry degrades the jurisdiction
// check silently rather than failing it. It was silent because nothing read
// the snapshot's date. This reads it.
//
// Deliberately independent of the cache above: health has to answer when the
// registry is NOT loaded, which is exactly the moment someone is looking.
// ---------------------------------------------------------------------------

export interface RegistryHealth {
  /** Live COUNT(*) of the addresses table — what the relay would actually use. */
  rows: number
  /** When the HMS export behind the current seed was read, ISO 8601. */
  snapshotAt: string | null
  /** Whole days since that snapshot, for a threshold to be read off. */
  ageDays: number | null
  /**
   * How many rows the seed claimed to write. A disagreement with `rows` means
   * a partially applied seed, which is a real risk for an 8.8 MB file applied
   * over the network — and would otherwise look like a working registry.
   */
  seededRows: number | null
}

interface RegistryMetaRow {
  snapshot_at: string
  row_count: number
}

export async function readRegistryHealth(
  db: D1Database,
  now: () => string,
): Promise<RegistryHealth> {
  const counted = await db.prepare('SELECT COUNT(*) AS n FROM addresses').all()
  const rows = Number((counted.results?.[0] as { n?: unknown } | undefined)?.n ?? 0)

  const meta = await db
    .prepare('SELECT snapshot_at, row_count FROM registry_meta WHERE id = 1')
    .all()
  const row = meta.results?.[0] as unknown as RegistryMetaRow | undefined

  if (row === undefined) {
    // Seeded before the meta table existed, or never seeded at all. Say so
    // rather than inventing a date.
    return { rows, snapshotAt: null, ageDays: null, seededRows: null }
  }

  return {
    rows,
    snapshotAt: row.snapshot_at,
    ageDays: ageInDays(row.snapshot_at, now()),
    seededRows: Number(row.row_count),
  }
}

function ageInDays(snapshotAt: string, nowIso: string): number | null {
  const then = Date.parse(snapshotAt)
  const at = Date.parse(nowIso)
  if (Number.isNaN(then) || Number.isNaN(at)) return null
  return Math.floor((at - then) / 86_400_000)
}
