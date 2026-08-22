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
