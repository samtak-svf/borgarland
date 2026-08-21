# 0002 — The apps post to our relay, never to the city directly

- **Date:** 2026-08-21
- **Status:** Accepted

## Context

The city's endpoint takes an anonymous multipart POST from any client, so an
Android or iOS app could file a report from the device with no backend at all.
It is also undocumented and unowned: Reykjavík can rename a field, add a captcha
or start checking `Origin` at any time, with no notice and no obligation to us.

Separately, the second half of this project is measuring the city's
follow-through, and there is nothing to measure it from — the city returns no
status, publishes no register and has no response-time data in its open-data
portal.

## Considered options

### A. Post from the device
- ➕ Nothing to run, nothing to pay for, no personal data passing through us.
- ➖ Absorbing a breaking change at the city costs an App Store review before
  anyone can file a report again. Days, for a change we did not choose.
- ➖ No record of what was sent, so no measurement is possible.

### B. A Cloudflare Worker relay with D1
- ➕ A breaking change costs a deploy.
- ➕ The only place a record of our submissions can live, which is what the
  follow-through measurement needs.
- ➖ Something to run, and personal data passing through us, which brings a
  privacy policy and a retention decision with it (#5).

### C. Direct now, relay later
- ➕ Least to build first.
- ➖ Means changing the send path in a shipped app, which is the migration nobody
  wants to do under time pressure.

## Decision

**Option B.** `worker/src/adapters/reykjavik.ts` is the only module allowed to
know the city's field names, slugs or URL.

## Consequences

- The relay validates the coordinate, because the city does not. `description` is
  the only field it enforces, so a report with no location would be accepted and
  nobody could act on it.
- The apps need a fallback for when the relay is unreachable: open the city's own
  form pre-filled in a web view. A report that takes thirty seconds beats one
  that never happens.
- A privacy policy becomes a release blocker (#5).
