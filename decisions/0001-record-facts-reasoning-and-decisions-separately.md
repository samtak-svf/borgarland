# 0001 — Record facts, reasoning and decisions in three separate places

- **Date:** 2026-08-21
- **Status:** Accepted

## Context

Everything this project knows about Reykjavík's reporting system was established
by black-box probing. The city documents none of it and is under no obligation
to keep any of it stable. Within a single evening the knowledge was already
spread across four markdown files, seven pull request bodies, commit messages
and a JSON blob, and the twelve category slugs existed in three copies that
could drift apart without anything failing.

Three different kinds of thing were being written down and they have different
readers. A program needs the slugs and the municipality codes. A human needs to
know why the pin is free and why we validate a coordinate the city does not. And
a future contributor needs to know which choices were already argued out, and
which of them were argued out and then reversed.

## Considered options

### A. One research document per topic, prose only
- ➕ Nothing to learn, reads well on GitHub.
- ➖ The data lives in markdown tables. The Worker, the Android app and the iOS
  app each retype the twelve categories, and the copies drift silently. This was
  already happening.
- ➖ No place for a decision that was reversed; it just disappears in a diff.

### B. Machine-readable facts, prose reasoning, MADR decisions
Three artifacts with one job each, and CI checking the facts against the live
site.
- ➕ One home per fact. `scripts/send-report.mjs` and `contract.yml` read the same
  file, so drift becomes a failing build rather than a wrong report.
- ➕ Provenance per claim. Every fact carries how and when it was established,
  which matters when none of it is documented and all of it can change.
- ➕ A reversed decision stays visible as reversed.
- ➖ Three places to look instead of one, and a rule about which is which.

### C. GitHub issues as the record
- ➕ Already there, already searchable.
- ➖ Decisions get buried under comments, and nothing machine-readable can read an
  issue body.

## Decision

**Option B.**

- [`data/reykjavik-form.json`](../data/reykjavik-form.json) — the facts, with
  `verifiedAt` and a note on how each was established. `scripts/send-report.mjs`
  and `.github/workflows/contract.yml` read it rather than restating it, and the
  contract job diffs it against the live category picker daily.
- [`docs/research/`](../docs/research/) and [`docs/incidents/`](../docs/incidents/)
  — the reasoning, and write-ups of things that went wrong.
- `decisions/` — this directory, in the MADR shape already used in
  `gudrodur/leidarvisir-fehirdis`.

## Consequences

- A fact changes in one place. Adding a thirteenth category means editing the
  JSON; the script and the contract check follow automatically.
- The markdown must stop carrying values and point at the JSON instead. Where it
  still shows a table for readability, the contract job is what keeps it honest.
- Someone will eventually put a fact in the prose because it was quicker. The
  daily contract job is the backstop that notices.
