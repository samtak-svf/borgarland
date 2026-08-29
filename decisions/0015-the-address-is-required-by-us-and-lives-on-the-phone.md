# 0015 — The reporter's address is required by us, and lives on the phone

- **Date:** 2026-08-29
- **Status:** Accepted

## Context

The city's form has exactly one field that gives the reporter anything back:
`email`. There is no phone field, no account, no ticket handle shown in the
app. The confirmation mail carries the report number, and a reply to it opens a
thread the city answers on — report 110474 was withdrawn that way and came back
with a request number, `RVK-58576`
([the incident](../docs/incidents/2026-08-21-filed-a-real-report.md)).

Both apps skipped the field on purpose. `MultipartBodyBuilder.swift` returned
`nil` for the part under the comment *"never collected"*, and `RelayClient.kt`
did the same. So every report ever filed from a phone was anonymous to the
city: it landed in the queue, and the person who filed it was told nothing
further by anyone but us.

The city treats the field as optional. It treats the coordinate as optional
too, and `data/reykjavik-form.json` has recorded the coordinate as
`"ourRule": "required by us"` since the form was first probed. The same
argument applies here and reaches the same answer.

## Decision

**The address is required by us, it belongs to the phone rather than to the
report, and the relay is not tightened yet.** Three parts, each load-bearing.

### Required by us

Neither app will build a request without one. The refusal is the contract's
own: `data/relay-request.json` marks `email` required, and the `valueFor(name)`
loop on both platforms already throws on a required part it cannot fill. One
gate, in the place the other four required fields are gated, rather than a
second rule living beside it in the interface. The screen disables its control
for the same reason it does for a missing description, but the screen is not
what enforces it.

### It belongs to the phone, and to nothing else

The phone is the **only** place it is stored. It is typed once, written to the
device beside `follow-ups.json` and the offline queue, and prefilled on every
later report; it travels with each report to the relay, which passes it to the
city and keeps none of it (migration 0004 drops the column, so the schema
refuses rather than relying on everyone remembering). The photo bytes have
worked exactly this way since the first schema, and `schema.sql` said so one
line above where the `email` column used to be. It is deliberately **not**
part of `QueuedReport`, and that has two consequences worth having:

- A report that waited in the queue goes out to whatever address the phone
  holds when it finally sends. Somebody who corrects a typo gets the
  confirmation at the corrected address, including for a report filed before
  the correction.
- `QueuedReport` is a persisted format, and adding a field to one is the
  silent-eviction trap that file's own comments are about — a record written by
  an earlier build must keep decoding. Nothing is added to it.

### The relay is not tightened

`required` in the contract is read by the two **apps**. The Worker reads that
file for the unknown-field allowlist alone and parses the email as optional, so
it keeps accepting a report without one.

This is the ordering rule from `AGENTS.md` running in the direction that is
easy to miss. The familiar half is that an app must not ship a field the relay
has not learned. The other half is that a relay must not start requiring a
field the installed builds do not send: builds 6 and 7 are on testers' phones
right now and send no address, and a relay that required one would answer 400
to every report they file. The app can be fixed by a deploy; those phones
cannot. The relay follows once no such build remains, and
`worker/tests/contract.test.ts` names itself as the test to delete when it
does.

## What this changes about 0013, and what it does not

[0013](0013-the-follow-up-asks-the-phone-not-the-person.md) chose to have the
follow-up ask the phone rather than the person, and part of its reasoning was
that the app collects no email and the database holds no contact detail. **The
second half of that is no longer true**, and this record is where a reader
finds that out.

The decision itself is untouched and stays right. The follow-up still asks the
phone, still keys on an id generated on the device, and still needs no way to
reach anybody — so it does not become an email question now that an address
exists. That is worth keeping precisely because the two could be conflated: one
address, going to the city for the city's own confirmation, is a smaller thing
than a contact database we ask questions from.

## Consequences

- **The phone is the only place the address is stored.** The relay forwards it
  and keeps none of it: migration 0004 drops the `email` column, so `reports`
  has nowhere to put one and a careless INSERT cannot put it back. It was
  already excluded from the logs (`worker/src/app.ts`), and the event stream's
  allowlist (`data/relay-events.json`) names no free-text field at all, so the
  address cannot travel that channel even by mistake. Not even its length is
  instrumented: a length is a small thing to know about an address and there is
  no question it would answer. In dry run the answer echoes the city payload,
  address included — that is the caller being shown what would have been sent,
  back to the app that just sent it, and it is stored nowhere.
- **[#5](https://github.com/samtak-svf/borgarland/issues/5) is a smaller
  question than it would otherwise be.** The app now collects personal data
  rather than only a coordinate and a photograph, which is a real change to
  what a privacy policy has to say. But it says it about ONE device and one
  onward recipient — the address lives on the phone that typed it and goes to
  the city, and the operator of this relay holds no register of addresses to
  describe, secure, or answer a subject-access request about.
- What counts as an address is written twice, once per platform, with the same
  table of cases pinned in both test suites. Deliberately loose: a strict
  pattern rejects addresses that work, and the cost of that is somebody who
  cannot file at all.

## Options that lost

**Leave it optional and ask nicely.** The field would be blank on most reports,
which is the situation we have, and the person filing would not know that
silence was the consequence of a field they skipped.

**Collect a phone number too.** There is nowhere to put one. The city's form
has no such field, so it could only travel inside the description — personal
data in free text, in a work queue, in a column we would then have to reason
about separately. Rejected outright.

**Tighten the relay at the same time.** Symmetrical, tidy, and it would have
broken every build already on a tester's phone.
