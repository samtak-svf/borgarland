# 0003 — The walking test excludes two of the city's categories

- **Date:** 2026-08-21
- **Status:** **Superseded by [0004](0004-walking-test-governs-interaction.md)** the same day

## Context

The scope test was set as *a human walking with a phone*. Applying it to the
city's twelve categories appeared to exclude two.

## Decision

Nine categories plus `almenn-abending` as a catch-all. `heimilissorp` and
`bilastaedasjodur` were left out of the app.

## Why it was wrong

The test was applied to the **city's description text** rather than to what
people actually report. Read that way `heimilissorp` looks like a service
complaint and `bilastaedasjodur` looks like account administration. But a full or
damaged bin on a private lot is a physical object standing at a coordinate,
visible from the pavement, and it photographs itself exactly like a pothole. So
does a broken meter, a bent sign, a barrier that will not lift.

And the property those two were punished for is shared by all twelve.
`umferdaroryggi` can be a pure opinion that a junction feels dangerous;
`almenn-abending` usually is one. **Every category has a non-photographic tail.**
Singling out two for it was over-fitting.

A second argument was given up too easily in reaching this decision: removing a
category the city maintains causes mis-routing inside their own triage, because
the report still gets filed, just under the wrong heading.

## Kept, not deleted

This record stays so the reversal is visible. See
[0004](0004-walking-test-governs-interaction.md) for what replaced it, and PRs
#9 and #10 for the arguments on both sides.
