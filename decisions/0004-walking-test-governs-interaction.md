# 0004 — The walking test governs the interaction, not the taxonomy

- **Date:** 2026-08-21
- **Status:** Accepted, supersedes [0003](0003-scope-excludes-two-categories.md)

## Context

The product test is *can a person walking with a phone meet this thing and
photograph it*. [0003](0003-scope-excludes-two-categories.md) applied that test
to the city's category list and dropped two of the twelve. That was wrong: it
judged categories by the city's description text rather than by what people
actually report, and it punished two categories for a non-photographic tail that
all twelve have.

The test itself is right. It was applied to the wrong object.

## Considered options

### A. Drop the two categories (what 0003 did)
- ➖ Deletes a category the city maintains, so the report still gets filed under
  the wrong heading and we have created mis-routing in their triage.
- ➖ Judges a category by its description rather than by its use.

### B. Carry all twelve, draw the line in the interaction
- ➕ The same product results — you still cannot use this to argue about a
  parking bill — without deleting anything the city has.
- ➕ Consistent with the decision to always post the Icelandic form: do not create
  triage problems for the people on the other end.
- ➖ The boundary now lives in interaction design rather than in a list, which is
  a weaker thing to point at in review.

## Decision

**Option B.** All twelve categories are in the app. The boundary is:

- **The camera is the entry point.** The app opens on it; no path starts with a
  form.
- **A coordinate is required.** The city does not enforce this; we do.
- **No desk mode.** No flow for disputing a charge, chasing an application, or
  filing an idea with nothing attached. Anyone who wants that has the city's own
  form, and the app should say so rather than pretend to be it.

`almenn-abending` is reworded in the interface: the net under a broken bench or a
fallen tree, never a suggestion box.

## Consequences

- `scripts/send-report.mjs` and `data/reykjavik-form.json` carry all twelve and
  now agree with the app. They document the **endpoint**, not the product, and a
  note in both says so — the two can diverge again and the divergence must not be
  "fixed" by trimming the map.
- Category ordering does the work the exclusion was trying to do: season and
  recency put what you are likely to be standing in front of first.
