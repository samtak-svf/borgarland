// The municipality check. The city validates nothing — not even that a
// coordinate exists, let alone where one falls (see docs/research/payload-map.md
// and data/reykjavik-form.json validation.onlyDescriptionIsEnforced) — so a
// pothole in Kópavogur would reach a Reykjavík work queue that cannot act on it.
//
// The check reads Staðfangaskrá's municipality code (SVFNR) of the nearest
// registered address: 0000 is Reykjavíkurborg, anything else is not ours to
// file. This module speaks the registry's vocabulary (SVFNR), not the city
// form's — the city's field names, slugs and URL belong only to the adapter.

import type { AddressPoint, Registry } from './registry'

/** Staðfangaskrá's code for Reykjavíkurborg ("0000" in the CSV). */
export const REYKJAVIKURBORG_SVFNR = 0

export type JurisdictionCheck =
  | { ok: true; nearest: AddressPoint }
  | { ok: false; reason: 'outside-reykjavik'; nearest: AddressPoint }
  | { ok: false; reason: 'unknown'; nearest: null }

export function checkJurisdiction(registry: Registry, lat: number, lng: number): JurisdictionCheck {
  const nearest = registry.nearest(lat, lng)
  if (nearest === null) {
    // No address at all within reach: the registry is empty or the point is
    // somewhere the register does not cover. Fail closed — never file a report
    // whose jurisdiction cannot be established.
    return { ok: false, reason: 'unknown', nearest: null }
  }
  if (nearest.svfnr === null || nearest.svfnr !== REYKJAVIKURBORG_SVFNR) {
    return { ok: false, reason: 'outside-reykjavik', nearest }
  }
  return { ok: true, nearest }
}
