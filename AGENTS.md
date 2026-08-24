# Borgarland — project guide

> Canonical agent instructions. `CLAUDE.md` is a symlink to this file, so Claude
> Code, Cursor, Codex and any other agent host read the same content. Edit
> `AGENTS.md`.

Native Android and iOS app that files a citizen report (ábending) with
Reykjavík from a photo and a coordinate. Public, MIT, built by Samtak svf.

Read [docs/research/reykjavik-reporting-api.md](docs/research/reykjavik-reporting-api.md)
before touching anything that talks to the city. It is the whole factual basis
for this project and it was established by black-box probing, not documentation.

## Before you change app code: the skills outrank your memory

**Android — Google's skills decide.** They publish 21 official ones
([github.com/android/skills](https://github.com/android/skills), Apache-2.0),
installed here as the `android-skills` plugin: edge-to-edge and IME insets,
adaptive layout, theming, Navigation 3, CameraX, R8, testing setup, Play. On
anything they cover, read the `SKILL.md` before writing the code rather than
after. This is not deference for its own sake. #110 was fixed by
`Modifier.imePadding()` placed **before** `verticalScroll()`, and a hand-written
note in this machine's own skills directory had the order backwards — appending
the modifier the obvious way would have shipped a quieter second bug on top of
the one being fixed. Three corrections in one line, from the people who own the
framework.

**iOS — nobody's skills decide, because Apple publishes none.** Checked
2026-08-24: `apple/skills` and every obvious variant is a 404, and no repository
under `org:apple` matches. Their move was to put the Claude Agent SDK inside
Xcode 26.3, which is no help here. What is installed is community work —
`swiftui-pro` and `swift-testing-pro`, Paul Hudson, MIT — and it is **evidence,
not law**. Two specific cautions: Hudson's own index says listing is not
endorsement, and `swiftui-pro` assumes iOS 26 and Swift 6.2 while
`ios/project.yml` targets **iOS 17.0 and Swift 5.9**, so its "use the modern
API" advice is regularly unbuildable here. There is no Mac on this machine, so
CI is the only compiler and a wrong suggestion costs a whole build to discover.

**Then verify on the device.** `android-ux` is the local companion for that half
and defers to Google for everything about the code. Its first rule is the one
this project learned the expensive way: *the screenshot is the instrument, take
it before you theorise.* #110 was in every screenshot already captured while an
agent read accessibility trees and blamed its own taps.

A `PreToolUse` hook (`~/.claude/scripts/mobile-skills-guard.mjs`) says this once
per platform per session on the first touch of `.kt` or `.swift`, including
edits made through the shell. If you are reading this instead, the hook did its
job.

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

**A report is written to the phone before it is sent, and it carries its own
id.** Both halves came out of the same field test, on the same phone, nine
minutes apart: a tester filed the same ábending twice because the screen never
said the first one had worked, and a send in airplane mode lost the report
([`2026-08-23-ios-reykjavik-offline-and-denial`](data/field-tests.json)). The
two sends are 34.9 seconds apart in that timeline and the airplane-mode failure
is 8 min 52 s after the first of them, by `atMs`, which is the phone's own clock
and the only one that measures what the person experienced.

The queue is iOS-only and `data/platform-parity.json` records why; the id is on
both. The id is 32 lowercase hex, generated per report by the app, and the relay
stores it as the row's own primary key, so a repeat is answered with the row
that already exists rather than becoming a second one. That makes a retry and a
double press the same harmless thing, which neither side can otherwise tell
apart. The queue refuses when it is full instead of evicting: every other policy
throws away something somebody filed, silently.

**Deploy the relay before shipping an app that uses a new part of the request.**
The Worker rejects any part `data/relay-request.json` does not name, which is
the guard that makes a stale app fail loudly — and it points both ways. A build
that sends a field an older relay has never heard of gets `unknown-field` on
every send. Measured on 2026-08-23, against the live relay, by an app that had
been built four minutes earlier.

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

`almenn-abending` **is** reworded in the interface. The city calls it
suggestions, praise and ideas; here it is the net under a broken bench, a fallen
tree, a collapsed fence — a walker's find with no category of its own. Both
pickers show it as **Annað í almannarými**, with a line underneath saying what
belongs there, from `data/category-labels.json` (#40). Never present it as a
suggestion box.

Both pickers read that file, so the check is one grep of it rather than a
memory of a screen. Worth saying because the obvious check is worse. iOS build 4
was cut before the labels file was read at all; build 5, uploaded 2026-08-24 and
VALID in TestFlight, is the first iOS build that reads it. **Build 5 has now
been run**, and by more people than the relay can see. App Store Connect records
**three** internal testers on build 5 as of 2026-08-24, with fourteen sessions
between them; the relay recorded **one** walk, at 11:58, accepted and written up
as [`2026-08-24-ios-build-5-first-run`](data/field-tests.json). This sentence
said "once" until the tester list was actually read, which is the same mistake as
every other one on this page: a count taken from the record nearest to hand
rather than from the thing being counted. **And it still does not settle the
label**, because that one walk chose `heimilissorp`. The build carrying the
change has been walked; the change has not. Which tester made that walk is not
knowable — App Store Connect names who installed, the telemetry names no device,
and nothing joins the two. **On Android somebody has now seen it.** The picker rendered
`Annað í almannarými` with its help line on an SM-S918B on 2026-08-24, read off
the device and matched to the file byte for byte, and the category was then
walked by hand to a report row — recorded as
[`2026-08-24-android-ime-fix-and-the-label-on-a-screen`](data/field-tests.json).
The 2026-08-23 run that #101 was filed about is in the same file, and that entry
is careful about what it cannot say: the telemetry carries no device identifier,
so which phone it was is a memory rather than a measurement. True of the event
BODY, which is what that entry meant and what `data/relay-events.json` enforces.
It was false of the transport until 2026-08-24: Android's default `User-Agent`
named the handset model on every request, and three models were visible in the
relay's logs before #128 replaced it with `Borgarland/<version>`. The allowlist
governs what the app sends, never what the platform adds underneath it.

**A build existing and a build having been walked are different claims.** This
paragraph has now been wrong five times, and the fifth failed differently from
the other four: "nobody has installed build 5" was *true when it was written*
and stopped being true at 11:58 the same day, while the sentence sat here for
hours saying otherwise — and in two issue bodies as well, which is where most of
the cost was. A sentence that reports the current state of the world has a shelf
life, and this file is not a place to store one without saying when it was
measured.

The other four were wrong on the day they were written. The third was a
correction that cited `data/field-tests.json` for an observation the file did
not contain; the fourth was this one still saying the run was recorded nowhere
**one commit after the same session recorded it** (#113). Both directions of the
same mistake, and the second was made by the person who had just written the
first correction.

So the check is not "grep before you claim". It is **grep again after you change
the record**, because the thing that most often falsifies a sentence here is
your own last commit.

**And grep for the CLAIM, not for the sentence you remember writing.** The
correction above announced three carriers. There were five. `README.md` said the
build "has not yet been installed by anyone" and `ReportQueue.swift` said it "is
installed nowhere" — the same assertion twice, in the public front door and in a
comment whose reasoning depended on it, and a search for `nobody has installed`
matches neither. The commit that found two carriers by widening a pattern then
stated a count from the pattern it had just been burned by. A prose claim has as
many spellings as the people who wrote it, so search for the several ways it
could be said, or state no number at all — which is what the paragraph two above
already tells you to do.

This paragraph twice said the opposite of the truth, in opposite directions. It
first claimed the rewording existed when it did not; the correction then claimed
it did not exist, and stayed after it was built. Both times the sentence
described an intention rather than the tree. The check is one grep of
`data/category-labels.json`, which is why the file exists.

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

One job each. Putting a fact in the wrong one is how they drift.

No number in that sentence any more: it said "four" while the table held eight,
which is what a count in prose does the third time the list grows.

| Where | What |
|---|---|
| [`data/reykjavik-form.json`](data/reykjavik-form.json) | **Facts** about the city's form, with how and when each was established. `scripts/send-report.mjs` and `.github/workflows/contract.yml` read it. Change a fact here first. |
| [`data/relay-request.json`](data/relay-request.json) | **Facts** about the request the apps send to OUR relay, in our vocabulary only. Both sides read it: the Worker rejects any part it does not name, and both apps build the request from it. A request-contract fact belongs here, never in the city's facts file and never in prose. |
| [`data/relay-events.json`](data/relay-events.json) | **Facts** about the client event stream the apps send to OUR relay. Its allowlist is the privacy boundary: every field is a number, a boolean or a fixed enum, and it deliberately names no free-text field, so a description or a coordinate cannot travel this channel even by mistake. Adding a string field here is a privacy decision, not a schema change. |
| [`data/relay-outcomes.json`](data/relay-outcomes.json) | **Our words** for what the relay answered, one sentence per outcome, in the language of the person filing. Separate from the city's facts for the same reason as the labels file: those record what the CITY says, this is what WE say to somebody about what happened. No Icelandic sentence for a relay answer belongs in Swift or Kotlin — both apps read this, and the mapping returns nothing rather than inventing a fallback. `worker/tests/outcomes.test.ts` holds it to every error code the Worker's own source can answer with, so a code with no sentence fails the build. |
| [`data/category-labels.json`](data/category-labels.json) | **Our words** for a category, where the city's are wrong for someone standing in front of the thing. The only place an app may override a label from the facts file, and separate from it on purpose: that one is a faithful record of what the city says, this is where we disagree. A slug absent here renders the city's own name, which should stay the common case. |
| [`data/platform-parity.json`](data/platform-parity.json) | **Facts** about which capabilities each app has, and the INTENT for each: parity, one-sided with a written reason, or neither-yet. `scripts/check-parity.mjs` detects the truth from the source and fails CI when it disagrees. The file does not assert what exists; that is the point. |
| [`data/field-tests.json`](data/field-tests.json) | **Observations** from a build in a hand, on a real device, against the live relay. Each entry keeps what was OBSERVED apart from what was CONCLUDED: the timeline and the report row are transcribed from D1 and must not be edited to fit a later understanding, while `findings` is interpretation and may be revised. `scripts/check-field-tests.mjs` validates every timeline against the event allowlist, because an event that could not cross the wire cannot have been observed. The defects that reach this file are the ones no test and no CI run can see. |
| `private/testers.json` **(gitignored, not in this repo)** | **People.** Who has been asked to test, on which channel, what they were told and what happened, plus `howToInvite` — the invite-flow traps, each one written the day somebody hit it. It is gitignored because it holds real names, addresses and chat identifiers and this repository is public. It is listed here anyway, because a file a future session does not know about gets re-derived from chat scrollback, and that is how a person gets asked twice or forgotten. |
| [`docs/research/`](docs/research/), [`docs/incidents/`](docs/incidents/) | **Reasoning**, and write-ups of what went wrong. |
| [`decisions/`](decisions/) | **Choices**, MADR shape, with the options that lost. A superseded record stays, marked superseded. |

The reasoning behind this split is [decision 0001](decisions/0001-record-facts-reasoning-and-decisions-separately.md).

**One of those files is not in the repository, on purpose.** `private/testers.json`
holds the tester roster and the contact log, and `private/` is gitignored — the
same convention `samtak-vefur` uses for anything carrying a name or an address.
Everything in it is personal data about volunteers, so it must never be
committed, quoted in an issue, or pasted into a PR body. What belongs in public
is the *lesson*, not the person: when an invite goes wrong, the trap goes in
`howToInvite` there and, if it is general, into the `play-console` skill.

It earns its place because the invite flow has more traps than the app does.
Play notifies a new internal tester of nothing at all; the opt-in URL works only
with the track id and not the app id; and tapping that URL inside a chat app's
own browser cannot complete the opt-in, which every tester invited over
Messenger or Discord will do first. All three were found by watching one person
try, on 2026-08-24.

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
