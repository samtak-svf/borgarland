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

The scope test is not "does the city accept it" but **is this a thing a person
walking with a phone can meet and photograph**. The app is the walking subset of
the city's form, not a reimplementation of it.

Nine of the twelve categories pass: `holur-i-gotu`, `snjor-og-halka`,
`numerlausir-bilar`, `gras-og-grodur`, `ruslafotur`, `gotusopun`, `nidurfoll`,
`ljosastaurar`, `umferdaroryggi`. Every one is a physical object standing in the
public realm that photographs itself at a coordinate.

Two fail and are **not** in the app:

- `heimilissorp` — waste collection on private property. You are at home, not
  walking, and it is a service complaint rather than a thing in the public realm.
- `bilastaedasjodur` — parking charges, car parks, residents' permits. Account
  administration, which a photograph does nothing for.

`almenn-abending` stays, but reworded. The city defines it as suggestions,
praise and ideas; in this app it is the net under a broken bench, a fallen tree,
a collapsed fence — things a walker meets that have no category of their own.
Present it as *something else in the public realm*, never as a suggestion box.

So: **nine categories and one catch-all, ten chips.**

A consequence worth keeping: all nine ask the same question — was the physical
thing fixed — on a comparable clock. The two that were dropped would have
muddied the follow-through measurement, because a dispute over a residents'
permit is not the same measurement as a pothole being filled.

**`scripts/send-report.mjs` keeps all twelve.** It is the map of what the city
accepts, not the app's interface. Do not trim it to match the app; the two are
different artifacts and the difference is deliberate.

## Location comes from the photo, not from an address

The city's form leads with "Sláðu inn heimilisfang". That is the wrong primitive
here. As Biggi put it when the idea started: *the bin has no address, only the
coordinate that came with the photo.* So: EXIF GPS first, device fix as
fallback, map correction optional, and reverse geocoding only to fill the city's
fields after the fact.

## Never file a real report as a test

`.github/workflows/contract.yml` probes the city's endpoint with a deliberately
incomplete payload and asserts the `400`. That proves reachability and the
multipart shape and creates nothing. Do not extend it into a real submission —
one manual end-to-end report at the end of a phase is fine; automated ones waste
a city employee's time.

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
