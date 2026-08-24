# 0010 — The report carries its own id, and the relay stores it as the row

- **Date:** 2026-08-23
- **Status:** Accepted

## Context

On 2026-08-23 a volunteer tester filed the same ábending twice, thirty-five
seconds apart. Two rows in D1, the same category, and both carrying the byte
count of the SAME photograph, the one captured at `atMs 27511` — the session
holds three photo-captured events and the other two carry different counts and
were never sent. One report, filed twice ([field test
`2026-08-23-ios-reykjavik-offline-and-denial`](../data/field-tests.json), #85).

He pressed the button again because the screen never said the first press had
worked — it showed him the relay's raw 201 body and he asked whether the app was
connected to anything at all (#77). That half is fixed by saying a sentence.
This decision is about the other half, which does not depend on anybody reading
a screen.

Neither side could tell that press from a retry, and **the request carried
nothing either of them could have used to**. `data/relay-request.json` named six
parts and none of them identified the report; `worker/src/db.ts` inserted a
fresh row per POST. The relay's own `id` column already carried a comment
calling it "the id the app talks about" — it just was not the app that said it.

The same gap sits under the offline queue ([0002](0002-relay-not-direct-post.md)
put the send behind a relay; #73 put a queue in front of it). A queued report
retried after an outage is indistinguishable from a second report, so
at-least-once delivery of a **report** could not be made safe the way it was for
telemetry, where a duplicate event is legible and a hole is not.

## Considered options

### A. Deduplicate on the server from the content
- ➕ No contract change, nothing to ship in an app.
- ➖ The relay cannot tell a deliberate repeat from an accidental one. Somebody
  photographing two identical bins on the same street corner is a real report,
  and guessing costs them it.
- ➖ Every heuristic is wrong in one of the two directions and silent about which.

### B. Rely on the app not offering the press
- ➕ Free, and worth doing anyway: the button now says Sent and is disabled.
- ➖ It is a mitigation in the app for a guarantee that has to hold at the relay.
  A retry, a crash, a background wake and a second device all bypass it.
- ➖ It leaves the queue's at-least-once retry unsafe by construction.

### C. A client-generated id on the request, stored as the row's primary key
- ➕ Makes a retry and a double press the same harmless thing, which is exactly
  what neither side can otherwise distinguish.
- ➕ No schema change and no migration: `id` is already `TEXT PRIMARY KEY` and
  already means this.
- ➕ The queue already generates one id per report and threw it away at the
  boundary; this is the id travelling rather than a second one invented.
- ➖ A seventh part in a contract whose order is load-bearing, so four separate
  checks have to be told about it.
- ➖ It must be optional, because a build already in TestFlight sends none — and
  an app without it cannot be protected.

## Decision

**C.** The app generates 32 lowercase hex per report, the same shape the relay
generates for a report that arrives without one. The relay stores it as the
row's own primary key and answers a repeat with the row that already exists, at
200 rather than 201.

The lookup happens **before** the category, the coordinate and the jurisdiction
are examined: a report the relay has taken must not be refused on a second press
because something else about the request changed.

The field is optional and stays optional until every build in a hand sends it.
Build 5 does and was uploaded 2026-08-24; build 4 does not and is what the two
testers have installed.
`data/relay-request.json` says in those words that an app without it cannot be
protected, so "optional" is not read as "not needed".

## Consequences

- Deploy the relay **before** shipping an app that uses a new part of the
  request. The Worker rejects any part the contract does not name, which is the
  guard that makes a stale app fail loudly and points both ways: a build sending
  a field an older relay has never heard of gets `unknown-field` on every send.
  Measured on 2026-08-23 against the live relay.
- The lookup and the insert are separated by the whole validation pipeline, so
  two concurrent requests with the same id can both find nothing. In dry run the
  primary key decides and the loser is answered with the row that won. **In live
  mode the city is posted to before either insert, so the same race defeats
  [0006](0006-never-press-submit.md)'s one-submission gate** — that was #98, and
  it was closed on 2026-08-24 before the relay was ever armed. The gate is now
  the write: one conditional INSERT that succeeds only while no live row exists,
  performed before the city is asked. See [0006](0006-never-press-submit.md).
- The id is client-chosen and unauthenticated, and holding one reads the stored
  row through the existing GET. It is 128 bits from a secure source on both
  platforms, so guessing is not a route; it is still a capability rather than a
  meaningless number, and the privacy policy (#5) should say so.

## References

- #85, #88, #98; PR #95
- [`data/relay-request.json`](../data/relay-request.json) `fields.reportId`
- `worker/src/app.ts`, the duplicate check; `worker/src/db.ts` `isDuplicateKey`
- [`data/field-tests.json`](../data/field-tests.json),
  `2026-08-23-ios-reykjavik-offline-and-denial`
