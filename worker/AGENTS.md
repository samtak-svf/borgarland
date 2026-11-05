# Worker relay context

> Path-scoped context, loaded when you read or edit a file under this directory.
> Read this directly before any wrangler, deploy or registry lookup work that opens no file here. Root rules in [AGENTS.md](../AGENTS.md) still apply (agent-config#1482 step 4).

## Addresses: use the registry, not the city

The city's address endpoints are Staðfangaskrá passed through unchanged —
verified to the last decimal against the HMS export. Do not call them. Use
**`iceaddr-ts`**, a zero-dependency, edge-native port already built for
Cloudflare Workers. Depend on the **published package** (`iceaddr-ts` on npm,
MIT, source at [gudrodur/iceaddr-ts](https://github.com/gudrodur/iceaddr-ts)),
the same way `xj-greenfield` consumes it. Never point a dependency at a local
checkout: this repository is public, and a path into one machine's home
directory resolves nowhere else.

That also gives us reverse geocoding, which reykjavik.is does not have anywhere.
Put the nearest registered address in the description we send, so the crew can
find a bin that has no address of its own. The block also names the register it
came from, says how far away it was, and prints the coordinate the lookup ran
against, because a crew member who receives an address on its own has no way to
tell it is a lookup and not where the reporter stood
([decision 0020](../decisions/0020-the-crew-block-carries-the-coordinate-it-was-looked-up-from.md), #202).

The Reykjavík subset is 23,057 addresses and 0.25 MB gzipped, small enough to
ship on a phone and answer with no signal. It does not ship on the phone.
[Decision 0009](../decisions/0009-the-registry-stays-in-the-relay.md) keeps the
registry in the relay, and the relay carries the **full national** registry
rather than the subset, because a coordinate in Kópavogur has to find a
Kópavogur address or the municipality check cannot fail it. Neither app has any
address capability at all.

**Check the municipality before sending.** The city validates nothing — not
even that a coordinate exists, let alone where it falls — so a pothole in
Kópavogur would reach a Reykjavík queue that cannot act on it. Reverse-look the
coordinate to its nearest address and read `SVFNR`: `0000` is Reykjavíkurborg.
Anything else, say so instead of filing. The city's own map bounds are useless
for this; they cover the whole capital region and out past Þingvellir.

**And ask how far away "nearest" was, which is the other half of the check.**
The register holds Icelandic addresses and nothing else, so the scan answers for
every point on Earth: a tester in Seattle resolved to a lighthouse in Suðureyri
5,630 km away, and that lighthouse's `SVFNR` decided whether his report was
filed. Beyond ten kilometres the answer is refused as
`jurisdiction-unknown` and no address is offered with it, because at that
distance the address is not a place but an artefact of a register covering one
country. Ten was measured rather than picked: the farthest point inside
Reykjavík probed sits 3.31 km from a registered address, and the table it was
chosen against is in `worker/src/jurisdiction.ts` beside the constant.

What no distance bound fixes, and what a point register cannot answer at all: a
coordinate the wrong side of a municipal boundary whose nearest registered
address is still a Reykjavík one passes. Only the boundaries themselves would
catch that, and a test says so rather than leaving it to be rediscovered.

**The registry is a convenience, never a constraint.** Picking an address does
not snap the report to it; the marker is free and moving it clears the address
field. The coordinate is the only thing submitted. Never snap a report to the
nearest house. Detail: [docs/research/addresses-and-the-registry.md](../docs/research/addresses-and-the-registry.md).

## Cloudflare

The Worker and its D1 live on **Samtak svf.'s** Cloudflare account, the one that
serves `api.samtak.is`. Switch before any wrangler operation:

```bash
eval "$(node ~/.claude/scripts/switch-cf-profile.mjs samtak)"
```

Create the D1 with `--jurisdiction eu`. A jurisdiction can only be set at
creation and can never be added afterwards; a plain `wrangler d1 create`
silently drops the guarantee, and finding that out later means recreating the
database.
