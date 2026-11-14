# Relay, report queue and deploy order

> Moved verbatim from the root `AGENTS.md`, where the rule stays as one line under the heading **Architecture**. Read this on the trigger named in the root's "Rule detail" table.

The apps do **not** post to the city directly. Behind a relay, a breaking change
at the city costs a deploy; from the app it costs an App Store review before
anyone can report anything again. The relay is also the only place the
follow-through measurement can live.

**A report is written to the phone before it is sent, and it carries its own
id.** Both halves came out of the same field test, on the same phone, nine
minutes apart: a tester filed the same ábending twice because the screen never
said the first one had worked, and a send in airplane mode lost the report
([`2026-08-23-ios-reykjavik-offline-and-denial`](../../data/field-tests.json)). The
two sends are 34.9 seconds apart in that timeline and the airplane-mode failure
is 8 min 52 s after the first of them, by `atMs`, which is the phone's own clock
and the only one that measures what the person experienced.

The queue is iOS-only and `data/platform-parity.json` records why; the id is on
both. The id is 32 lowercase hex, generated per report by the app, and the relay
stores it as the row's own primary key, so a repeat is answered with the row
that already exists rather than becoming a second one. That makes a retry and a
double press the same harmless thing, which neither side can otherwise tell
apart. The queue refuses when it is full instead of evicting: every other policy
throws away something somebody filed, silently.

**A report carries the address the city will answer to, and the phone keeps
it.** The city's form has exactly one field that gives the reporter anything
back — no phone number, no account, no ticket handle in the app — and both apps
skipped it until #163, so every report filed from a phone was anonymous to the
city and its author heard nothing from anyone but us. It is now **required by
us and optional to the city**, the same override the coordinate gets and for
the same reason. The address belongs to the DEVICE rather than to the report:
typed once, kept beside the queue and the follow-ups, prefilled, and read at
send time — so a report that waited in the queue goes out to whatever address
the phone holds now, and `QueuedReport`'s persisted format is untouched.

**The relay is deliberately NOT tightened to match, and that asymmetry is the
ordering rule pointing the other way.** `required` in `data/relay-request.json`
is read by the two apps; the Worker reads that file for the unknown-field
allowlist alone and still parses the email as optional. Builds 6 and 7 are on
testers' phones and send no address, so a relay that required one would answer
400 to every report they file — and unlike the app, those phones cannot be
fixed by a deploy. Decision 0015, and `worker/tests/contract.test.ts` names
itself as the test to delete when the relay does follow.

**Deploy the relay before shipping an app that uses a new part of the request.**
The Worker rejects any part `data/relay-request.json` does not name, which is
the guard that makes a stale app fail loudly — and it points both ways. A build
that sends a field an older relay has never heard of gets `unknown-field` on
every send. Measured on 2026-08-23, against the live relay, by an app that had
been built four minutes earlier.

**The same rule covers `data/relay-events.json`, and there it fails quietly.**
The Worker bundles the events allowlist at build time too (`worker/src/events.ts`
imports it), so a build that sends an event name the live relay has never heard
of is refused the same way. Two things make this the more dangerous half. The
refusal is *batch-level*: `validateEvent` rejects the whole POST with
`invalid-event-batch`, so one unknown name destroys every event that travelled
with it, including the ones the relay does know. And the app never finds out,
by design: `outcomeForStatus` treats 400-499 as REJECTED and drops the batch
rather than retrying, while `/api/events` and the report path are separate
handlers in `worker/src/app.ts` — so the report itself goes through, the person
filing sees success, and only the measurement disappears.

Measured on 2026-08-24, not assumed: a real walk lost its entire batch to one
unknown name while its report row landed normally, and the walk left no trace to
read afterwards, because the trace was the thing that was refused. Deploy first,
then ship the build.
