# 0024 — The app does not offer the city's own form when the relay is unreachable

- **Date:** 2026-09-15
- **Status:** Accepted

## Context

#2's acceptance list has carried this box since before the relay existed:

> Fallback: when the relay is unreachable, open the city's own form pre-filled in
> a Custom Tab

The motivation is sound, and it is the one thing a walking app has to answer:
the person has photographed the thing, the relay is not answering, and the
report is going to be lost unless something happens. What the box proposes is a
second submission path — and it is the only box in that list that decisions
taken since would refuse.

Two of those decisions are load-bearing here.

**Decision 0002**: the apps post to our relay, never to the city directly,
because a breaking change at the city costs a deploy behind the relay and an App
Store review from the app. The relay is also the only place the follow-through
measurement can live — and it is where the report is stored before it is sent,
which is what makes the one real submission possible at all.

**The jurisdiction check.** The city validates nothing on the coordinate; a
pothole in Kópavogur reaches a Reykjavík queue that cannot act on it. The relay
refuses that report, and the refusal is the reason the report is *stored* rather
than filed blindly. A pre-filled Custom Tab is the person filling in the city's
form themselves: the coordinate goes in, the check does not run, and the
measurement loses the report.

`AGENTS.md` states the boundary in the product's own terms, under the scope
test: *"No desk mode… Someone who wants that has the city's own form, and the
app should say so rather than pretend to be it."* Pointing at the form is in
scope. Driving somebody through it is the app pretending to be it.

## Decision

**No pre-filled fallback. When the relay cannot be reached, the app says so and
points at the city's own form; it does not carry the report there.**

What the box's motivation actually needs already has an answer that keeps the
report inside our system: **the queue**. iOS has one (decision 0011 — it refuses
rather than evicts, and every other policy throws away something somebody
filed), and Android does not, which is the real gap behind this box and is filed
as its own issue. A queued report goes out when the relay is back, with its
coordinate checked and its row stored, which a Custom Tab cannot do.

## Consequences

- A person with no relay and no queue on Android is told the send failed and
  that the city's form is the alternative, with a link. The report is not
  silently filed somewhere the project cannot see it.
- The jurisdiction check cannot be bypassed by a phone. That is the property
  decision 0005 and the `MAX_NEAREST_ADDRESS_KM` work exist to hold, and it
  stays true because there is no second path.
- The measurement keeps every report it is ever going to get. A Custom Tab
  fallback would make the follow-through numbers a lower bound with no way to
  say by how much.
- The Android queue becomes the answer to "the relay is unreachable" rather than
  a nicer-to-have, which is the ordering the iOS side already followed.

## Options that lost

**Pre-filled Custom Tab, exactly as the box says.** Would get the report filed,
and loses the coordinate check, the stored row, the measurement and the
deploy-versus-review argument in one step. It is the only suggestion in #2 that
contradicts a decision record, and the contradiction is the point.

**A Custom Tab with no pre-filling — just the city's form.** Refused on the same
grounds as the pre-filled one for anything the app carries; **allowed** as a
link, which is what this decision says to do. The difference is who is filling
in the form: the person, or us.

**Send to the city directly, with the relay as a copy.** Breaks decision 0002
and, worse, makes the relay a bystander: it would learn about a report after the
city did, which is the opposite of a place where a report is stored before it is
sent.

**Queue on Android and keep the fallback as well.** Two paths out of one failure
is how a failure becomes untestable: whichever is rarer stops being exercised,
and the field-test record would have to cover both. The queue alone is the
smaller thing to build and the only one that keeps the report.
