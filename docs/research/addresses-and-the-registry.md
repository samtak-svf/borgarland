# The city is serving Staðfangaskrá, and we can serve it ourselves

The address endpoints behind the city's form are the national address registry
(Staðfangaskrá) passed through unchanged. Established 2026-08-21 by comparing
the city's response to the registry's own export.

## The evidence

The city's `/abendingar/addressInfo?a=Laugavegur 1&p=101` returns:

```json
{"street":"Laugavegur","address":"Laugavegur 1","district":"0000","zip":"101",
 "geometry":{"lat":64.14658919,"lng":-21.93279823}}
```

The corresponding row in HMS's `Stadfangaskra.csv`:

```
HNITNUM 10017495 | POSTNR 101 | HEITI_NF Laugavegur | HUSNR 1 | SVFNR 0000
N_HNIT_WGS84 64.14658919 | E_HNIT_WGS84 -21.93279823
```

Identical to the last decimal, and the odd `"district":"0000"` is the registry's
`SVFNR` column showing through. The field names on the search endpoint say the
same thing: `fasteignarheiti_nefnifall` and `postnumer_id` are registry
vocabulary, not something a website would invent.

So the city is not a source of address data here. It is a proxy in front of one
we can read directly.

## What that changes

**We already have the client.** `iceaddr-ts` — a zero-dependency, edge-native
port of the data layer of Sveinbjörn Þórðarson's `iceaddr`, written for
Cloudflare Workers, at `~/Development/projects/stadfangaskra/`. The Worker relay
runs on Workers. Use it rather than writing a lookup.

**Two dependencies drop off.** `/location/addresses` and
`/abendingar/addressInfo` stop being part of the surface we rely on. Both stay
in `payload-map.md` as documentation of the city's form, but nothing we ship
needs to call them.

**We gain the thing the city does not have.** There is no reverse geocoding
anywhere on reykjavik.is. With the registry in hand, a coordinate can be turned
into the nearest registered address — which is exactly what the crew going to
empty a bin on a footpath needs, and exactly what the form cannot express. It
belongs in the description we send:

> Full ruslafata við göngustíginn. Næsta skráða hús: Laugarásvegur 3.

**It fits on the phone.** Reykjavík's postcodes hold 23,057 addresses out of the
registry's 139,347 rows. Reduced to street, number, letter, postcode and a
coordinate at six decimals, that is 1.07 MB of compact JSON and **0.25 MB
gzipped**, across 1,126 distinct streets. Small enough to ship in the app, so
address search and reverse geocoding both work with no signal — which matters
for something used while walking.

Source: `https://hmsstgsftpprodweu001.blob.core.windows.net/fasteignaskra/Stadfangaskra.csv`,
the public HMS export `iceaddr-ts` already fetches. Refresh it on a schedule;
treat the bundled copy as a cache with a date, not as truth.

## The pin is free, and that is the whole point

Worth stating plainly because the form's own copy hides it: choosing an address
does **not** snap the report to that address. It flies the map there, and the
marker can then be dragged anywhere — between houses, onto a path, into a park.
Move it and the address field empties. What is submitted is only ever the
coordinate.

That is not a loophole, it is the design, and it is what makes the case that
started this project ordinary rather than awkward. A litter bin standing on a
footpath has no address, and the form never wanted one.

For the app it means the address registry is a **convenience, never a
constraint**: a way to fly the map, a way to label a report for the crew. The
coordinate from the photo remains the primary input, and nothing is ever snapped
to the nearest house.
