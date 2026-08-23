// The municipality check. The city validates nothing — not even that a
// coordinate exists, let alone where one falls (see docs/research/payload-map.md
// and data/reykjavik-form.json validation.onlyDescriptionIsEnforced) — so a
// pothole in Kópavogur would reach a Reykjavík work queue that cannot act on it.
//
// The check reads Staðfangaskrá's municipality code (SVFNR) of the nearest
// registered address: 0000 is Reykjavíkurborg, anything else is not ours to
// file. This module speaks the registry's vocabulary (SVFNR), not the city
// form's — the city's field names, slugs and URL belong only to the adapter.
//
// What it is NOT, and cannot be with a point register: a polygon test. A
// coordinate a few hundred metres the wrong side of a municipal boundary whose
// nearest registered address is still a Reykjavík one passes, and no distance
// bound fixes that — only the boundaries themselves would. The bound below
// answers a different question, which is whether the nearest address is near
// enough to answer at all.

import type { AddressPoint, Registry } from './registry'

/** Staðfangaskrá's code for Reykjavíkurborg ("0000" in the CSV). */
export const REYKJAVIKURBORG_SVFNR = 0

/**
 * How far the nearest registered address may be and still answer the question.
 *
 * The register covers Iceland and nothing else, so the nearest-address scan
 * answers for every point on Earth. Without a bound it answers for Seattle, and
 * the SVFNR of a lighthouse 5,630 km away decides whether a report is filed
 * (#75). That is the benign direction; the costly one is a coordinate far from
 * anywhere whose nearest address happens to carry 0000 and is waved through.
 *
 * Ten kilometres, measured rather than picked, against the 139,360-row snapshot
 * of 2026-08-22:
 *
 *     Reykjavík centre                    0.00 km
 *     Viðey                               0.50 km
 *     Esja summit                         0.94 km
 *     Heiðmörk                            1.49 km
 *     Kjalarnes                           3.31 km   ← farthest point IN Reykjavík probed
 *     Hvannadalshnúkur                    9.23 km
 *     15 km offshore in Faxaflói         10.44 km
 *     middle of Vatnajökull              24.27 km
 *     Seattle                          5,630.89 km
 *
 * So a person standing anywhere in Reykjavík has three times the headroom, and
 * a coordinate that is not in Iceland misses by three orders of magnitude. The
 * remote interior of the country falls outside the bound too, which is correct
 * for what this refusal MEANS: not "you are not in Iceland" but "no registered
 * address is near enough for its municipality code to answer for this point".
 */
export const MAX_NEAREST_ADDRESS_KM = 10

export type JurisdictionCheck =
  | { ok: true; nearest: AddressPoint; km: number }
  | { ok: false; reason: 'outside-reykjavik'; nearest: AddressPoint; km: number }
  | { ok: false; reason: 'unknown'; nearest: null; km: number | null }

export function checkJurisdiction(
  registry: Registry,
  lat: number,
  lng: number,
  maxKm: number = MAX_NEAREST_ADDRESS_KM,
): JurisdictionCheck {
  const found = registry.nearestWithDistance(lat, lng)
  if (found === null) {
    // No address at all: the registry is empty. Fail closed — never file a
    // report whose jurisdiction cannot be established.
    return { ok: false, reason: 'unknown', nearest: null, km: null }
  }
  if (found.km > maxKm) {
    // There IS a nearest address, and it is too far away to answer for this
    // point. `nearest` is deliberately null on this branch: a caller that
    // passed the row on would put an address thousands of kilometres away in
    // front of somebody as though it meant something, which is exactly what
    // the first field test did.
    return { ok: false, reason: 'unknown', nearest: null, km: found.km }
  }
  if (found.row.svfnr === null || found.row.svfnr !== REYKJAVIKURBORG_SVFNR) {
    return { ok: false, reason: 'outside-reykjavik', nearest: found.row, km: found.km }
  }
  return { ok: true, nearest: found.row, km: found.km }
}
