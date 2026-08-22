# Borgarland — project guide

> Canonical agent instructions. `CLAUDE.md` is a symlink to this file, so Claude
> Code, Cursor, Codex and any other agent host read the same content. Edit
> `AGENTS.md`.

Native Android and iOS app that files a citizen report (ábending) with
Reykjavík from a photo and a coordinate. Public, MIT, built by Samtak svf.

Read [docs/research/reykjavik-reporting-api.md](docs/research/reykjavik-reporting-api.md)
before touching anything that talks to the city. It is the whole factual basis
for this project and it was established by black-box probing, not documentation.

## The one rule that matters

**`worker/src/adapters/reykjavik.ts` is the only file allowed to know the
city's field names, category slugs, or URL.** Everything upstream speaks our own
vocabulary. The city's endpoint is undocumented and unowned; when it changes,
the blast radius has to be one file. If you find yourself writing `lat` or
`ruslafotur` anywhere else, that is the bug.

## Architecture

```
Android (Kotlin/Compose)  ─┐
                           ├─→  Worker relay  ─→  reykjavik.is form endpoint
iOS (Swift/SwiftUI)       ─┘         │
                                     └─→  D1: our record of what was sent, when
```

The apps do **not** post to the city directly. Behind a relay, a breaking change
at the city costs a deploy; from the app it costs an App Store review before
anyone can report anything again. The relay is also the only place the
follow-through measurement can live.

## What belongs in the app: a human walking with a phone

The scope test is **can a person walking with a phone meet this thing and
photograph it**. That test governs the *interaction*, not the taxonomy — a
distinction worth stating, because an earlier version of this section got it
wrong and dropped two categories over it.

**All twelve categories are in the app.** Every one of them can carry a
photograph of a physical object at a coordinate: a damaged bin on a private lot
is as photographable from the pavement as a pothole, and a broken meter, a bent
sign or a barrier that will not lift are as physical as a dead street light.

The mistake to avoid is judging a category by the city's description text rather
than by what people actually report through it. Read that way, `heimilissorp`
looks like a service complaint and `bilastaedasjodur` looks like account
administration — but **every category has a non-photographic tail**.
`umferdaroryggi` can be a pure opinion that a junction feels dangerous, and
`almenn-abending` usually is one. Singling out parking for a property all twelve
share was over-fitting.

So the boundary is drawn in the interaction instead:

- **The camera is the entry point.** The app opens on it. There is no path that
  starts with a form.
- **A coordinate is required.** The city does not enforce this; we do. See the
  location section below.
- **No desk mode.** No flow for disputing a charge, chasing an application, or
  filing an idea with nothing attached to it. Someone who wants that has the
  city's own form, and the app should say so rather than pretend to be it.

`almenn-abending` **should be** reworded in the interface, and is not. The city
calls it suggestions, praise and ideas; here it is the net under a broken bench,
a fallen tree, a collapsed fence — a walker's find with no category of its own.
Present it as *something else in the public realm*, never as a suggestion box.

This paragraph was written in the present tense as though the rewording existed.
It does not: both apps render the city's own string verbatim
(`DetailsScreen.kt`, `DetailsScreen.swift`), which is also why the picker shows
"Almenn ábending" as a category and "Almenn ábending" as its kind. That is
tracked in #40, which reads as a cosmetic collision and is really this
requirement going unbuilt.

**`scripts/send-report.mjs` and `payload-map.md` document all twelve** because
that is what the city accepts. They now agree with the app, but keep the
distinction in mind: those files map the endpoint, this section governs the
product.

## Location comes from the photo, not from an address

The city's form leads with "Sláðu inn heimilisfang". That is the wrong primitive
here. As Biggi put it when the idea started: *the bin has no address, only the
coordinate that came with the photo.* So the coordinate travels with the
picture, a map would be a correction rather than an entry point, and reverse
geocoding only fills the city's fields after the fact. (No map exists in either
app yet; the sentence describes the intended shape, not a built surface.)

**Which source comes first depends on where the photo came from, and testing on
a real phone reversed the order we assumed.** A photo the app captures itself
carries no EXIF GPS at all, because CameraX does not write it unless asked, so
the device fix is the primary source on that path and not the fallback. EXIF is
the primary source for a photo chosen from the gallery — which is also the path
where it is most often missing, since messaging apps strip it. Ask both, label
which one answered, and refuse when neither does.

**The city accepts `image/jpeg`, `image/png` and `image/gif`, and an iPhone
shoots HEIC.** On our own capture path that is a setting, not a constraint: iOS
names its own codec through `AVCapturePhotoSettings`, so ask for JPEG and never
transcode a photograph we took ourselves. The gallery is where it bites, on both
platforms. A picked HEIC has to be converted, and conversion runs *larger* than
the original (4.14 MB became 4.78 MB at quality 90); `ExifGps.read` understands
only JPEG and reads a HEIC as having no location at all; and on iOS a picked
photo read as a `UIImage` arrives with its EXIF gone, so read the file bytes
instead. Measured against a real original, along with what else the GPS block
carries and the reverse lookup running end to end:
[docs/research/photos-exif-and-formats.md](docs/research/photos-exif-and-formats.md).

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
find a bin that has no address of its own.

The Reykjavík subset is 23,057 addresses and 0.25 MB gzipped, small enough to
ship on a phone and answer with no signal. It does not ship on the phone.
[Decision 0009](decisions/0009-the-registry-stays-in-the-relay.md) keeps the
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

**The registry is a convenience, never a constraint.** Picking an address does
not snap the report to it; the marker is free and moving it clears the address
field. The coordinate is the only thing submitted. Never snap a report to the
nearest house. Detail: [docs/research/addresses-and-the-registry.md](docs/research/addresses-and-the-registry.md).

## Never press submit on the city's live form

Not with a network interceptor in place, not with the network throttled, not
under any circumstance. The button files a real report into a real work queue.

This is stated as a rule about **the button** rather than about intent, because
the previous wording said "never file a real report as a test", was followed,
and a real report was filed anyway — see
[docs/incidents/2026-08-21-filed-a-real-report.md](docs/incidents/2026-08-21-filed-a-real-report.md).
The safeguard was a patch to `window.fetch` that never ran, and it had not been
tested before the button was pressed. A safety mechanism you have not seen fire
is not a safety mechanism.

What is allowed instead:

- **The probe.** `node scripts/send-report.mjs --category <slug> --probe` posts a
  deliberately incomplete payload that the validator must reject. It *cannot*
  succeed, which is the property that makes it safe, and
  `.github/workflows/contract.yml` runs it daily on that basis.
- **Reading the client bundle** when a payload needs observing rather than
  constructing. It is static and already downloaded; reading it cannot send.
- **One real submission, once, deliberately**, at the end of a build, with a real
  problem at a real location. That is a decision to take on purpose, never a step
  in a test.

`scripts/send-report.mjs` will not send without `--send` for the same reason.
Do not add a shortcut around that flag.

## Where things are written down

Four artifacts, one job each. Putting a fact in the wrong one is how they drift.

| Where | What |
|---|---|
| [`data/reykjavik-form.json`](data/reykjavik-form.json) | **Facts** about the city's form, with how and when each was established. `scripts/send-report.mjs` and `.github/workflows/contract.yml` read it. Change a fact here first. |
| [`data/relay-request.json`](data/relay-request.json) | **Facts** about the request the apps send to OUR relay, in our vocabulary only. Both sides read it: the Worker rejects any part it does not name, and both apps build the request from it. A request-contract fact belongs here, never in the city's facts file and never in prose. |
| [`docs/research/`](docs/research/), [`docs/incidents/`](docs/incidents/) | **Reasoning**, and write-ups of what went wrong. |
| [`decisions/`](decisions/) | **Choices**, MADR shape, with the options that lost. A superseded record stays, marked superseded. |

The reasoning behind this split is [decision 0001](decisions/0001-record-facts-reasoning-and-decisions-separately.md).

## Conventions

- Feature branch and a PR. Never commit or push to `main`; lefthook blocks both.
- `lefthook install` after cloning.
- Conventional prefix, then a descriptive sentence rather than an imperative:
  `fix(worker): the city rejects a photo over 8 MB, and we were finding out in the app`.
- **No AI authorship markers** anywhere — commits, PR titles, PR bodies, issues.
  No `Co-Authored-By:` naming an AI, no `🤖 Generated with` footer, no AI in the
  author or committer identity. Enforced locally by lefthook and authoritatively
  by `.github/workflows/ai-authorship.yml`.
- Everything written in English: commits, PRs, issues, code comments, docs. When
  an English artifact names a domain term that has an established Icelandic name,
  give the English first with the Icelandic in parentheses on first use — "a
  citizen report (ábending)". App UI strings are Icelandic.
- CI runs on GitHub-hosted runners. This repo is public, so `ubuntu-latest` and
  `macos-latest` minutes are free; there is no reason for a self-hosted runner
  here.

## Cloudflare

The Worker and its D1 live on the **personal** Cloudflare account, the one that
serves `api.samtak.is`. Switch before any wrangler operation:

```bash
eval "$(node ~/.claude/scripts/switch-cf-profile.mjs personal)"
```

Create the D1 with `--jurisdiction eu`. A jurisdiction can only be set at
creation and can never be added afterwards; a plain `wrangler d1 create`
silently drops the guarantee, and finding that out later means recreating the
database.

## Origin

The idea is Biggi Veira's. The conversation it came from, transcribed with
speaker attribution and the requirements extracted, is private and lives outside
this repo at `~/fedora-setup/projects/borgarland/conversations/`.
