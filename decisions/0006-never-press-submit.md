# 0006 — Never press submit on the city's live form

- **Date:** 2026-08-21
- **Status:** Accepted

## Context

`AGENTS.md` already carried a rule: *never file a real report as a test*. It was
followed. A real report was filed anyway.

Research needed the exact payload the browser builds, to diff against what
`scripts/send-report.mjs` constructs. The approach was to patch `window.fetch`
in the page so the submission would be captured and a synthetic response
returned, then fill the real form and press submit. React Router did not submit
through the patched function. The interceptor never ran, and **report 110474**
reached Reykjavík's service desk describing nothing real.

The existing rule failed because it addressed **intent** while the failure was
**mechanical**. Full write-up:
[docs/incidents/2026-08-21-filed-a-real-report.md](../docs/incidents/2026-08-21-filed-a-real-report.md).

## Considered options

### A. Keep the intent-based rule, be more careful
- ➖ Already tried. It was obeyed and did not prevent the outcome.

### B. Allow the browser, require a verified interceptor first
- ➕ Keeps a genuinely useful technique available.
- ➖ The verification is the hard part, and the tempting shortcut is to skip it
  under time pressure. That is exactly what happened.
- ➖ Frames an irreversible action as safe once a box is ticked.

### C. Forbid the button outright
- ➕ Mechanical, not a judgement call. Nothing to assess in the moment.
- ➖ Loses the ability to observe a real submission. In practice this costs
  nothing, because everything the browser sends was already determined by
  reading the client bundle and probing the validator.

## Decision

**Option C.** Never press submit on the city's live form. Not with an
interceptor, not with the network throttled, not under any circumstance.

What is allowed instead:

- **The probe.** `send-report.mjs --probe` posts a deliberately incomplete
  payload the validator must reject. It *cannot* succeed, which is the property
  that makes it safe rather than any care taken around it.
- **Reading the client bundle**, when a payload needs observing rather than
  constructing. It is static and already downloaded; reading it cannot send.
- **One real submission, once, deliberately**, at the end of a build, with a real
  problem at a real location. A decision taken on purpose, never a step in a test.

## What enforces this now

Written as a rule, this held for one day. On 2026-08-21 a report was filed by
accident anyway — 110474, withdrawn by email that evening
([the write-up](../docs/incidents/2026-08-21-filed-a-real-report.md)) — because a
rule about care is only as good as the care.

Since 2026-08-23 the "one" is a property of the relay rather than of anyone's
attention: a second submission cannot happen even with the secret still set,
even from a different client, and even after a redeploy. The "one" is a row in
D1 rather than a flag, because the database is the only thing that survives a
new isolate and a re-set secret.

**How it is enforced changed on 2026-08-24, and the first version did not
work.** It read a count and wrote the row after the city had already been posted
to, so two requests in flight at once both counted zero and both filed
(#98). The gate is now the write itself: a single conditional INSERT that
succeeds only while no live row exists, performed BEFORE the city is asked. The
answer to whoever loses is `409 live-send-already-used`, or the stored row if
they are the same report arriving twice. Two overlapping requests are what the
tests drive, because two sequential ones pass either way.

Hard-coded on purpose: a variable is one typo from being raised. Lifting this
should cost a code change and a review, which is exactly what going live for real
will be (#6) — delete that block then, deliberately, in its own PR.

## Consequences

- A safety mechanism you have not seen fire is not a safety mechanism. If the
  only test that would prove it works is the irreversible one, there is no test.
- `send-report.mjs` will not send without `--send`, and `contract.yml` asserts
  that default still holds. Do not add a shortcut around the flag.
- The deeper lesson is not in the rule: the endpoint had already been fully
  mapped by reversible means, and the browser was chosen anyway. Prefer the method
  whose failure costs nothing.

## The one was spent on 2026-08-30

Recorded here rather than left to be reconstructed, because this decision's
whole subject is a thing that can happen exactly once and it has now happened.

A grass strip in Grafarvogur, photographed at 01:17 and filed from the phone
through the armed relay. The city answered **200** with reference **110759**,
and its confirmation email reached the reporter one second later. The walk is
[`2026-08-30-android-the-one-real-submission`](../data/field-tests.json); the
report row is `de1eec5690759a72a0660ee67c677fb3`.

**The decision is unchanged and is now enforced by something other than itself.**
`reserveLiveReport`'s row is claimed, so a second live report is refused whatever
the switch says — the gate above is no longer a promise about the future but a
fact about the database. Lifting it is still a code change in its own PR.

Three things this makes concrete that the decision could only argue:

- **The safeguard was watched.** The gate was armed for minutes and disarmed
  immediately after, both by a deploy, both visible at `GET /api/health`. That
  is the two-part switch of [decision 0016](0016-the-live-send-gate-is-a-switch-you-can-see.md)
  doing the job it was built for four hours earlier, and it is the direct answer
  to the consequence above: a mechanism nobody has seen fire is not a mechanism.
- **The reversible method came first.** The whole request was validated against
  the production relay in dry run — jurisdiction, format, size, the exact
  `cityPayload` — before anything was armed. Nothing about the live send was
  discovered by sending it.
- **Report 110474 has a sibling now, and the pair is a measurement.** The two
  reference numbers this project has legitimately caused are 285 apart over 8.21
  days, which is the city's report volume at roughly 35 a day — recorded in
  `data/reykjavik-form.json` under `measurement.reportVolume`. The first of those
  numbers came from the incident this decision was written about. The second was
  taken on purpose, and it is the difference between the two that is worth
  anything.

## The "one" is one per DATABASE, not one per project

Recorded 2026-08-30, after a design review of [#184](https://github.com/samtak-svf/borgarland/issues/184)
read the mechanism rather than the claim.

`claimLiveReport`'s condition is `WHERE NOT EXISTS (SELECT 1 FROM reports WHERE
dry_run = 0)`, and it is scoped to the database it runs against. Today there is
one D1, so the guarantee and the sentence above agree. **A second database would
carry its own open budget** — an armed environment pointed at it could file
without limit, and the city has no test mode to file into.

This is not a defect to fix now; it is a claim that is wider than its mechanism,
which is the shape of thing this project would rather write down than rediscover.
Anything that adds a database inherits the obligation to say what stops it
sending: a switch committed off, a `CITY_SEND_KEY` never put, and a health
readout that names which environment is answering.
