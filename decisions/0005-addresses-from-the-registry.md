# 0005 — Addresses come from Staðfangaskrá, not from the city

- **Date:** 2026-08-21
- **Status:** Accepted

## Context

The city's form has two address endpoints, `/location/addresses` for search and
`/abendingar/addressInfo` for address-to-coordinate. Comparing their output to
HMS's own export showed the city is serving the national address registry
(Staðfangaskrá) unchanged: `Laugavegur 1` matched to the last decimal, and the
otherwise inexplicable `"district":"0000"` is the registry's `SVFNR` column
showing through.

Meanwhile the city has **no reverse geocoding anywhere**, which is the operation
this app most needs — a bin on a footpath has no address, and the crew sent to
empty it would like the nearest one.

## Considered options

### A. Call the city's endpoints
- ➕ Nothing to build, and they work today.
- ➖ Two more undocumented dependencies on a system we do not own.
- ➖ No reverse geocoding, because the city does not have it.
- ➖ Requires a network round trip, in an app used while walking.

### B. Read the registry ourselves via `iceaddr-ts`
`iceaddr-ts` is a zero-dependency, edge-native port of the data layer of
Sveinbjörn Þórðarson's `iceaddr`, written for Cloudflare Workers, which is what
the relay runs on. It is published on npm under MIT, source at
[gudrodur/iceaddr-ts](https://github.com/gudrodur/iceaddr-ts), and that
published package is what we depend on.
- ➕ Already exists and is already ours. Reuse rather than build.
- ➕ Reverse geocoding, which the city cannot do at all.
- ➕ `SVFNR` gives the jurisdiction check: `0000` is Reykjavíkurborg, and the city
  validates nothing, so a Kópavogur pothole would otherwise land in a Reykjavík
  queue.
- ➕ Reykjavík is 23,057 of 139,347 rows, **0.25 MB gzipped**, so it ships on the
  phone and both search and reverse lookup work with no signal.
- ➖ A bundled copy is a cache that goes stale and needs refreshing.

## Decision

**Option B.** The city's address endpoints stay documented in
`payload-map.md` as part of the form, but nothing we ship calls them.

## Consequences

- The bundled registry is a cache with a date, not truth. Refresh on a schedule.
- The nearest registered address goes in the description we send, so a report
  about something with no address is still actionable.
- **The registry is a convenience, never a constraint.** Picking an address does
  not snap the report to it — the marker is free and moving it clears the field.
  The coordinate is the only thing submitted, and nothing is ever snapped to the
  nearest house.
