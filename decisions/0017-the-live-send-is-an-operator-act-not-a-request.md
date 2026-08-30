# 0017 — The live send is an operator act, not something a request can cause

- **Date:** 2026-08-30
- **Status:** Accepted
- **Supersedes:** the scoping half of [0016](0016-the-live-send-gate-is-a-switch-you-can-see.md).
  0016's two-part switch stands and is unchanged; what it gates is different.

## Context

[Decision 0016](0016-the-live-send-gate-is-a-switch-you-can-see.md) made the
gate visible. It did not make it **selective**, and a relay serving more than one
person needs both. Armed, every report from every phone went to the city. Once
[decision 0006](0006-never-press-submit.md)'s one-submission row was claimed,
an armed relay answered `409 live-send-already-used` to every tester who walked.
Both were observed on 2026-08-30, which is why the relay was disarmed within
minutes of filing report 110759.

The requirement is to let one person, on one occasion, from their own phone,
file for real, while everyone else gets an ordinary dry run.

### Two designs failed the same test, and the second was ours

The discriminating question is:

> Can a client that knows everything the legitimate client knows still force a
> live send?

`POST /api/reports` has **no authentication of any kind**. The live decision
held only because no request input reached it — `resolveLiveSend` reads
environment bindings and nothing else.

**Scoping by the reporter's address** (#178) fails: `email` is client-controlled
and unvalidated (`worker/src/app.ts`), and the scoped address is the person's
own, so the client knows it by construction.

**Scoping by the report id** fails the same way, one step further out. The id is
a 128-bit nonce generated on the device, which looks like an improvement — but it
is still a value the client carries at send time, so a client that knows it can
send a different report under it. On an unauthenticated endpoint, **carrying a
value and claiming it are the same bytes in the same field.** That design was
written, reviewed, and rejected before it was built.

The failure is structural, not a matter of picking a better value. Any design
where the request decides has this shape.

## Decision

**A report can no longer reach the city by arriving.** Every report is stored as
a dry run, without exception and whatever the configuration says. The city is
posted to by exactly one path:

```
POST /api/reports/:id/promote     Authorization: Bearer <CITY_SEND_KEY>
```

Three things follow, and each is the point rather than a side effect.

### Nothing in a report can cause a live send

Not a field, not a header, not an id. The property `config.ts` has always
claimed is now structural rather than argued: there is no live branch in the
report handler to reach.

### The operator sees the content before deciding

This is the real difference from every scoping design. Scoping authorises
*blind* — the operator names who or what may go live before anything is
composed. Promotion is a judgement about a report that already exists, and the
photographs are readable through `GET /api/reports/:id/photo/:n` behind the same
credential, because that judgement cannot be made from a category and a
coordinate.

### An unscoped reporter gets a dry run, never an error

The failure #178 was opened about is gone by construction rather than by a rule:
the gate is not on the arrival path at all.

## What it costs, stated plainly

**Photographs are now stored.** The relay kept none; promotion needs them,
because a report cannot be reviewed or filed without its evidence. They go to an
R2 bucket created with `--jurisdiction eu`, the same guarantee the D1 has and for
the same reason, and **a lifecycle rule on the bucket expires every object after
30 days** — deliberately a property of the store rather than a cron somebody has
to remember.

**The address is still stored nowhere.** It is supplied at promote time: one
value, typed once, for the one report. Migration 0004 and
[decision 0015](0015-the-address-is-required-by-us-and-lives-on-the-phone.md)
stand — the relay holds no register of addresses.

**Promoting somebody else's report files it in their name, to their address.**
The city answers the reporter, which is right. It also means a tester whose
report might be filed for real should know that and agree to it. That is a
matter of asking them, not of code, and it is written here so it is not
discovered later.

**The person's app says "recorded".** From the app's side its send did not reach
the city, which is true, and `data/relay-outcomes.json` needs no new sentence.
They learn it went live from the city's confirmation email. Whether that is good
enough is left open until one real promote has been done.

## Consequences

- `worker/tests/promote.test.ts` carries the safety properties that used to live
  on the arrival path — one report ever, two in flight, the row flipped before
  the city is asked, the one staying spent on an unreachable city — plus the
  ones that are new: arriving cannot send however the relay is configured, a
  wrong credential of the same length is refused, and an expired photograph
  refuses the promote rather than filing without evidence.
- `GET /api/health` gains `oneSubmission`, the state it could not see: it
  reported `armed` while the row was already claimed, which is a relay that
  would have refused everything.
- Decision 0006 is untouched. This changes *who* may cause the one, never *how
  many*.
- When #6 lifts the one-submission row, promote is already the only live path,
  so the count gate and the operator gate keep their separate shapes.

## Options that lost

**Scope by email (#178) or by report id.** Both above. Rejected for the same
reason, which is the reason worth remembering: an identity in the request,
however unguessable, is a value the client carries.

**A client certificate installed on the one device (mTLS at the edge).** Passes
the forgery test most cleanly and scopes durably to a device. Rejected on cost
and blindness: Cloudflare mTLS configuration, a phone enrolment, a special build
with an iOS review cycle — and a gate whose enforcement `/api/health` cannot
report, which is exactly what 0016 was written to stop.

**A one-time ticket handed to the person and typed into the app.** The trap. It
has the shape everyone recognises as security — single use, short expiry,
delivered at the moment — and fails the test for the identical reason the email
did: the ticket is in the client at send time. It is also the most expensive
option, needing a contract change, new UI and new builds on both platforms, for
a property that does not survive.

**A short live window: arm for minutes, first report wins.** Zero machinery,
which is why it is tempting, and it is what was done manually on 2026-08-30. It
scopes to a clock rather than to a person, so a tester opening the app at the
wrong moment files for real. That is the incident this decision exists to
prevent, with a shorter timer.
