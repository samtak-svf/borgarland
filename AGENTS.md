# Borgarland — project guide

> Canonical agent instructions. `CLAUDE.md` is a symlink to this file, so Claude
> Code, Cursor, Codex and any other agent host read the same content. Edit
> `AGENTS.md`.

Native Android and iOS app that files a citizen report (ábending) with
Reykjavík from a photo and a coordinate. Public, MIT, built by Samtak svf.

Read [docs/research/reykjavik-reporting-api.md](docs/research/reykjavik-reporting-api.md)
before touching anything that talks to the city. It is the whole factual basis
for this project and it was established by black-box probing, not documentation.

## Rule detail (read on the trigger)

Each section below keeps its rule as one line. The full wording, its history and its measurements moved
verbatim to `docs/agents/` (agent-config#1482 step 4); read the file when its trigger fires.

| Detail file | Holds | Read it when |
|:--|:--|:--|
| [project-stage.md](docs/agents/project-stage.md) | Proof-of-concept status, the purpose limit, the 2026-08-31 north-star correction | before arguing from what the data is for |
| [app-code.md](docs/agents/app-code.md) | Verify on the device; the `mobile-skills-guard` hook | before app code |
| [relay-and-reports.md](docs/agents/relay-and-reports.md) | Phone-first queue and report id, the reporter address, deploy order and its measurements | before changing the request, the events, the queue or a deploy |
| [app-scope.md](docs/agents/app-scope.md) | The scope test, all twelve categories, the `almenn-abending` wording | before adding a flow, a category or a screen |
| [claim-history.md](docs/agents/claim-history.md) | Build 5/6/7 label sightings, the five wrong claims, grep-the-claim lessons | before stating what was built, installed or walked, in any file, README or issue |
| [location-and-photos.md](docs/agents/location-and-photos.md) | Device fix vs EXIF vs address; HEIC and JPEG | before location, photo or EXIF work |
| [live-form.md](docs/agents/live-form.md) | Why the rule is about the button, the incident, what is allowed instead | before anything that talks to the city's form |
| [where-things-live.md](docs/agents/where-things-live.md) | The one-job-each table and why `private/` exists | before recording a fact anywhere |
| [ci-runners.md](docs/agents/ci-runners.md) | Why CI is GitHub-hosted only | before adding a workflow or changing a runner |

## What stage this is, and what the data is for

**The app is a proof of concept**, and the data exists only to prove the app works. Never justify anything
by what the data could later become (#36): that is the collapse the purpose limit exists to prevent.

## Before you change app code: the skills outrank your memory

The Android paragraph is in `android/AGENTS.md` and the iOS one in `ios/AGENTS.md`; the rest binds both.

**Then verify on the device** (`android-ux`): the screenshot is the instrument, take it before you theorise.

## The one rule that matters

**`worker/src/adapters/reykjavik.ts` is the only file allowed to know the
city's field names, its URL, and the type, name and summary derived from a
category slug.** The slug itself is our vocabulary, shared by the apps and the
relay and sourced from `data/reykjavik-form.json`. The city's endpoint is
undocumented and unowned; when it changes, the blast radius has to be one file.
If you find yourself writing the city's raw field names (`lat`, say) or its URL
anywhere else, that is the bug.

## Architecture

```
Android (Kotlin/Compose)  ─┐
                           ├─→  Worker relay  ─→  reykjavik.is form endpoint
iOS (Swift/SwiftUI)       ─┘         │
                                     └─→  D1: our record of what was sent, when
```

- **The apps do not post to the city directly**: behind the relay, a break at the city costs a deploy, not an App Store review.
- **A report is written to the phone before it is sent and carries its own id**, the row's primary key, so a retry and a double press are the same harmless thing. The queue refuses when full, never evicts.
- **The reporter's address is required by us, optional to the city**, and belongs to the device; the relay deliberately stays optional (decision 0015).
- **Deploy the relay before shipping an app that uses a new part of `data/relay-request.json` or `data/relay-events.json`.** An unknown name is refused, and for events the whole batch vanishes silently.

## What belongs in the app: a human walking with a phone

**Can a person walking with a phone meet this thing and photograph it?** All twelve categories stay; the
camera is the entry point, a coordinate is required, and there is no desk mode. `almenn-abending` shows as
**Annað í almannarými** from `data/category-labels.json`; never present it as a suggestion box.

**A build existing and a build having been walked are different claims.** Date any sentence about the
current state, and after you change the record grep again for the CLAIM, not the sentence you remember,
in README, issues and code comments too.

## The location comes from the device at capture, not from an address

The device's GPS fix at capture is the only positional thing sent to the city. The nearest registered
address is a labelled note for the crew, never the location, and a report is never snapped to it. Ask our
own camera for JPEG; never transcode a photograph we took ourselves.

## Never press submit on the city's live form

Not with a network interceptor in place, not with the network throttled, not
under any circumstance. The button files a real report into a real work queue.

Use the `--probe`, which cannot succeed. The one deliberate real submission (110759) is spent; another is
a code change in its own PR (#6).

`scripts/send-report.mjs` will not send without `--send` for the same reason.
Do not add a shortcut around that flag.

## Where things are written down

One job each: facts in `data/*.json`, reasoning in `docs/`, choices in `decisions/`. `private/` (testers,
city mail) is gitignored, and nothing in it is ever committed, quoted in an issue or pasted into a PR body.

## Subtree context

Claude Code loads a nested `CLAUDE.md` (a symlink to the sibling `AGENTS.md`) only once a file in that
subdirectory is read or edited. Other hosts may not load it at all, and an action that opens no file there
(a deploy, a wrangler call, a new walk arriving) never triggers it. Read the file yourself in those cases.

| File | Holds | Read it when |
|---|---|---|
| [android/AGENTS.md](android/AGENTS.md) | Google's Android skills outrank memory | before Android app code |
| [ios/AGENTS.md](ios/AGENTS.md) | Why no Apple skills decide, and what the community ones are worth | before iOS app code |
| [worker/AGENTS.md](worker/AGENTS.md) | Addresses: use the registry, not the city; Cloudflare profile and D1 jurisdiction | before relay, registry or wrangler work |
| [data/AGENTS.md](data/AGENTS.md) | When new test data arrives (the seven-step check) | when a walk, screenshots or telemetry arrive |

## Check your work

| Surface | Run |
|:--|:--|
| Worker | `cd worker && npm run check` (typecheck, then vitest) |
| Repo-wide guards | `node scripts/check-parity.mjs`, `node scripts/check-app-path-filters.mjs`, and the other `scripts/check-*.mjs` |
| Android | Gradle runs on samtak-mac via `~/.claude/scripts/mac-remote.mjs` (see `android/AGENTS.md`) |

## Conventions

- Feature branch and a PR. Never commit or push to `main`; lefthook blocks both.
- `lefthook install` after cloning.
- Conventional prefix (`feat|fix|docs|ci|chore|refactor|test|perf|build|style|revert|workflow|ops`; the commit-msg hook refuses anything else), then a descriptive sentence rather than an imperative:
  `fix(worker): the city rejects a photo over 8 MB, and we were finding out in the app`.
- **No AI authorship markers** anywhere — commits, PR titles, PR bodies, issues.
  No `Co-Authored-By:` naming an AI, no `🤖 Generated with` footer, no AI in the
  author or committer identity. Enforced locally by lefthook and authoritatively
  by `.github/workflows/ai-authorship-guard.yml`.
- Everything written in English: commits, PRs, issues, code comments, docs. When
  an English artifact names a domain term that has an established Icelandic name,
  give the English first with the Icelandic in parentheses on first use — "a
  citizen report (ábending)". App UI strings are Icelandic.
- CI is GitHub-hosted only, on purpose; a new workflow inherits that and need not relitigate the lane.

## Origin

The idea is Biggi Veira's. The conversation it came from, transcribed with
speaker attribution and the requirements extracted, is private and lives outside
this repo at `~/fedora-setup/projects/borgarland/conversations/`.
