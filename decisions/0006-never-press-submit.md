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

## Consequences

- A safety mechanism you have not seen fire is not a safety mechanism. If the
  only test that would prove it works is the irreversible one, there is no test.
- `send-report.mjs` will not send without `--send`, and `contract.yml` asserts
  that default still holds. Do not add a shortcut around the flag.
- The deeper lesson is not in the rule: the endpoint had already been fully
  mapped by reversible means, and the browser was chosen anyway. Prefer the method
  whose failure costs nothing.
