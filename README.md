# Borgarland

Open the phone, point it at the problem, send. That is the whole app.

Reykjavík already takes citizen reports (ábendingar) — an overflowing litter
bin, a hole in the pavement, a dead street light — through a web form at
[reykjavik.is/abendingar](https://reykjavik.is/abendingar/senda-abendingu). The
form works. But nobody out on a walk in the city's public realm (borgarlandið)
is going to stop and fill it in on a phone, so the report never gets made and
the city never learns about the problem.

This is a native Android and iOS app that reduces the whole thing to: camera,
location, send.

Free software, no charge, no ads, no data resale. Built by
[Samtak svf.](https://samtak.is), a cooperative (samvinnufélag).

## Status

**Three parts exist and none of them has filed a report.** The feasibility
question is answered in
[docs/research/reykjavik-reporting-api.md](docs/research/reykjavik-reporting-api.md);
what is built on top of it is:

- **The Worker relay** (`worker/`), **deployed** at `borgarland.samtak.is` on
  Cloudflare, with D1 (`--jurisdiction eu`) holding the national address
  registry and our record of every report. In dry run.
- **The Android app** (`android/`), which has run on a real phone: camera,
  coordinate, category, description, and a POST to the relay. It has no release
  pipeline and ships to nobody ([#58](https://github.com/samtak-svf/borgarland/issues/58)).
- **The iOS app** (`ios/`), the same flow in SwiftUI, on top of a
  platform-independent `BorgarlandCore` package whose tests pin it to the same
  request contract the Android and Worker tests pin. Builds through `0.1.0 (6)`
  are in TestFlight, signed without a Mac. Build 4 was walked by two testers on
  2026-08-23; build 5 was installed by three testers on 2026-08-24, of whom the
  relay saw one walk; build 6 was walked the same evening, 45 minutes after it
  went VALID. Every run is in [`data/field-tests.json`](data/field-tests.json).

  This line has been stale twice in two days, in the same way both times. It
  said nobody had installed anything until 2026-08-24, having been written when
  that was true and left alone. It then said build 5 "has been run once" for
  eight hours after `AGENTS.md` had been corrected to three testers and fourteen
  sessions (#127) — the correction found the file it was looking at and stopped.
  A sentence here reports the state of the world, so it needs a date attached or
  a grep of the thing it describes; see **When new test data arrives** in
  `AGENTS.md`, which exists because of exactly this.

**Nothing in this repository has reached the city, and the relay cannot reach it
by accident.** Forwarding requires the deliberate `CITY_SEND_KEY` secret, which
does not exist; doing nothing leaves dry run
([decision 0002](decisions/0002-relay-not-direct-post.md)). And when it is
armed, the relay files exactly one report and refuses the second, because
[decision 0006](decisions/0006-one-real-submission.md)'s "one" is enforced in
code rather than remembered.

The short version: Reykjavík publishes no API, and no Icelandic municipality
implements Open311 — but the city's own form endpoint accepts an anonymous
`multipart/form-data` POST from any client, validated server-side, with no CSRF
token and no captcha. Every field is mapped in
[payload-map.md](docs/research/payload-map.md), and
[`scripts/send-report.mjs`](scripts/send-report.mjs) files a report from the
command line — including reading the coordinate out of a photo's EXIF.

That is enough to build on. It is also a dependency we do not own, which is what
shapes the architecture below.

## Shape

```
Android (Kotlin/Compose)  ─┐
                           ├─→  Worker relay (Cloudflare)  ─→  reykjavik.is
iOS (Swift/SwiftUI)       ─┘         │
                                     └─→  D1: our record of what was sent, when
```

Five decisions worth stating early.

**The location is the photo's, not an address.** The city's form leads with
"type in an address", but there is no address field in the payload at all: the
search exists only to move a map marker, and what gets submitted is always a
coordinate. For a litter bin standing on a path that is exactly right, because
it has no address — only the coordinate that came with the photo. So EXIF GPS
first and the device fix as fallback, both of which exist, and a map only for
correcting it, which does not exist on either platform yet
([#2](https://github.com/samtak-svf/borgarland/issues/2)).

**We validate the location, because the city does not.** `description` is the
only field the city enforces. A report with no coordinate would be accepted and
nobody could act on it, so the relay rejects it before the city sees it.

**A relay, not a direct post.** The app could POST to the city from the device
and skip a backend entirely. It should not. The endpoint is undocumented and can
change without notice; if the apps talk to it directly, every change costs an
App Store review before anyone can file a report again. Behind a relay it costs
a deploy. A scheduled contract test watches the endpoint so we hear about a
change from a red build rather than from a user.

**We keep our own record, because nobody else does.** The city does return a
reference number on success — we know because one was returned for a report
filed by accident — but there is nothing to do with it: no lookup, no status, no
public register, and no response-time data published anywhere. Its open-data
portal has 595 datasets and not one concerns ábendingar. A number you cannot ask
a question about is not a ticket. So
the second half of this project falls out of the first: an app that timestamps
its own submissions and later asks the reporter whether the thing actually got
fixed is the only instrument anyone has for measuring the city's follow-through.
That measurement is worth as much as the convenience.

**A graceful fallback, once it is built.** When the relay cannot be reached, the
app should open the city's own form pre-filled in a web view rather than
failing: a report that takes thirty seconds beats a report that never happens.
Neither app does this yet. Today both say they could not reach the relay and
stop, and the fallback is an open acceptance criterion in
[#2](https://github.com/samtak-svf/borgarland/issues/2).

## Scope

**A human walking with a phone.** That is the test, and it governs how the app
works rather than which of the city's categories it carries.

All twelve are in: potholes, ice, abandoned cars, vegetation, litter bins,
sweeping, drains, street lights, traffic safety, household waste, parking, and a
catch-all for the broken bench with no category of its own. Each one can carry a
photograph of a physical thing standing at a coordinate.

What the test rules out is the desk. The camera is the entry point, a coordinate
is required, and there is no flow for disputing a charge or filing an idea with
nothing attached to it. Anyone who wants that has the city's own form, and this
app should say so rather than pretend to be it.

Reykjavík only, to begin with. The capital area does not share one reporting
system — Mosfellsbær runs MainManager behind ASP.NET `__VIEWSTATE`, Hafnarfjörður
a Drupal module — so each additional municipality is real work, not a config
entry. Get one right first.

## What CI checks

Eight workflows, all on GitHub-hosted runners — this repo is public, so the
minutes are free and there is no reason for a self-hosted runner.

| Workflow | What it guards |
|---|---|
| `contract.yml` | The daily probe against the city's endpoint, so a change there arrives as a red build rather than as a user's failed report. It posts a deliberately incomplete payload the validator must reject: it *cannot* succeed, which is the property that makes it safe. |
| `relay-request-contract.yml` | That the Worker and both apps still agree with `data/relay-request.json`, plus the Swift and Kotlin unit tests. |
| `platform-parity.yml` | That iOS and Android have not drifted apart without someone writing down why (`data/platform-parity.json`). |
| `android-ci.yml` | ktlint, Android lint, a debug build and the unit tests. |
| `ios-ci.yml` | The SwiftUI shell builds for a simulator, unsigned. |
| `ios-release.yml` | On an `ios-v*` tag: archive, sign, upload dSYMs to Crashlytics, ship to TestFlight — without a Mac. |
| `field-tests.yml` | That a record in `data/field-tests.json` transcribes only events the relay's allowlist permits, so a hand-written transcript stays trustworthy. |
| `ai-authorship.yml` | That no commit or PR body carries an AI authorship marker. |

## Contributing

`lefthook install` after cloning. Feature branch and a PR; `main` is protected.
Conventions are in [AGENTS.md](AGENTS.md) — including the one about never filing
a real report as an automated test.

## License

MIT. See [LICENSE](LICENSE).
