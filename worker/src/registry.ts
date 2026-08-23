// In-memory index over the rows of the national address registry
// (Staðfangaskrá) that the relay needs: jurisdiction (SVFNR) and a human
// reading of the nearest address for the description we send.
//
// The rows are loaded from the D1 `addresses` table (see registry-loader.ts),
// which is seeded by scripts/refresh-registry.mjs from the HMS export via
// iceaddr-ts. The registry is a cache with a date, never truth — refresh it on
// a schedule and redeploy/restart to pick up the new rows.
//
// The full registry (all ~139k rows, not just Reykjavík) is required for the
// jurisdiction check to be correct: reverse-looking a Kópavogur point against a
// Reykjavík-only subset would find its nearest address in Reykjavík and
// wrongly pass it. Any point must be able to find its own municipality.

import { haversineKm } from 'iceaddr-ts'
import { postcodeLookup } from 'iceaddr-ts/postcodes'

export interface AddressPoint {
  /** Staðfangaskrá municipality code (sveitarfélagsnúmer); 0 is Reykjavíkurborg. */
  svfnr: number | null
  streetNf: string
  houseNumber: number | null
  houseLetter: string | null
  postalCode: string
  lat: number
  lng: number
}

export class Registry {
  private readonly rows: AddressPoint[]

  constructor(rows: Iterable<AddressPoint>) {
    this.rows = Array.from(rows)
  }

  get size(): number {
    return this.rows.length
  }

  /** The nearest registered address to a point, by great-circle distance. */
  nearest(lat: number, lng: number): AddressPoint | null {
    return this.nearestWithDistance(lat, lng)?.row ?? null
  }

  /**
   * The nearest registered address AND how far away it was.
   *
   * The distance is not decoration. The register holds Icelandic addresses
   * only, so every point on Earth has a nearest one and this scan always
   * answers: a coordinate in Seattle resolves to a lighthouse in Suðureyri
   * 5,630 km away, and a caller reading only the row cannot tell that from a
   * house across the street (#75).
   */
  nearestWithDistance(lat: number, lng: number): { row: AddressPoint; km: number } | null {
    let best: AddressPoint | null = null
    let bestKm = Infinity
    for (const row of this.rows) {
      const km = haversineKm({ lat, lng }, { lat: row.lat, lng: row.lng })
      if (km < bestKm) {
        bestKm = km
        best = row
      }
    }
    return best === null ? null : { row: best, km: bestKm }
  }
}

export function createRegistry(rows: Iterable<AddressPoint>): Registry {
  return new Registry(rows)
}

/** "Laugavegur 1, 101 Reykjavík" — the line the crew can walk to. */
export function describeAddress(row: AddressPoint): string {
  const house = row.houseNumber === null ? '' : ` ${row.houseNumber}${row.houseLetter ?? ''}`
  const place = postcodeLookup(row.postalCode)
  const city = place?.nominative ?? ''
  const tail = city === '' ? row.postalCode : `${row.postalCode} ${city}`
  return `${row.streetNf}${house}, ${tail}`.trim()
}
