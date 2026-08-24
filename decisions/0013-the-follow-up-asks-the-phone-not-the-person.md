# 0013 — The follow-up asks the phone, not the person

- **Date:** 2026-08-24
- **Status:** Accepted

## Context

`POST /api/reports/:id/outcome` has existed since the relay did. It is routed,
implemented and tested, and **nothing has ever called it** (#57). That is worse
than an ordinary unused endpoint, because measuring follow-through is one of the
two reasons the relay exists at all: the city returns no ticket id, exposes no
public register and publishes no response-time data, so the reporter's own later
answer to *was it fixed?* is the only signal that exists anywhere about whether
reporting works (#1).

#57 framed the choice as two options, and both are unattractive.

**Build the follow-up** as the issue described it, and the reporter has to be
contactable. Today they are not: the app never collects an email, and a
coordinate is not a person. Collecting one would turn an anonymous act into an
identified one, which is a privacy decision before it is a feature (#5), and it
would put a contact detail in a database that currently holds none.

**Delete the endpoint**, and a real capability goes because nobody got round to
using it. The issue says plainly that deleting a working capability is worse
than leaving it.

## Decision

Neither. **The app asks itself.**

The report id is generated **on the phone**
([0010](0010-the-report-carries-its-own-id.md)) — 32 hex, made by the app before
the report is sent. So the app already knows the ids of the reports it filed,
and nothing else has to be stored for it to ask about them later. The app keeps
its own small list of ids it sent, and after an interval asks the person holding
that phone whether the thing got fixed. The answer goes to the endpoint keyed by
the id, which the relay already has a row for.

**The relay learns one bit about a report it already knows about, and nothing at
all about who filed it.** No email, no account, no device identifier, no contact
of any kind. The follow-up loop exists and the privacy question #5 raises never
arises, because the thing being asked is the phone.

## Why fourteen days

Picked, not measured, and worth saying so. The city publishes no response-time
data — that absence is the whole reason this measurement exists — so there is no
figure to derive an interval from. Fourteen days is long enough that a pothole
crew could plausibly have been and gone, and short enough that somebody still
remembers filing it. It is a constant in one place and the first thing to change
once there is any real distribution of outcome timings to look at.

## Consequences

**The list is on the phone and never leaves it.** It holds ids the app itself
generated, when they were sent, and the category slug so the question can name
what it is asking about. Losing it (reinstall, cleared data) loses the ability to
ask, and that is the correct trade: the alternative is a server-side record of
who filed what.

**An unanswered report is asked once.** Being nagged about a bin is how an app
gets uninstalled, and a person who ignores the question has answered it. The
record is marked asked either way.

**This measures the reporter's belief, not the city's work.** Somebody who never
walks past the spot again will answer "not fixed" about a fixed pothole. That is
a real limit and the number should never be presented as the city's repair rate.
It is the only signal available, which is a different claim from being a good
one.

**Android first, iOS to follow.** `data/platform-parity.json` records it
`android-only` with this decision as the reason, rather than letting the gap
drift unnoticed. The relay side needs nothing: the endpoint has been waiting for
a caller since the day it was written.
