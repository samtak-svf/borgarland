# 0007 — Approach the city after the proof of concept, not before

- **Date:** 2026-08-21
- **Status:** Accepted

## Context

The app files through an endpoint the city never published. That is defensible
for a proof of concept and a poor basis for a user base: the city can change or
close it without notice, and being discovered is a weaker position than arriving
with something built.

Two other things are waiting on the same conversation. The ArcGIS service
`Hreinsun/Hreinsun_dev` advertises `Query,Update,Uploads,Editing` on an
anonymously readable REST endpoint — untested, and not to be tested. And report
110474 needs withdrawing, which is a separate and immediate contact.

## Considered options

### A. Tell them now
- ➕ Courteous, and forecloses the awkward version of the conversation.
- ➖ Invites them to close the endpoint before anything exists, and offers nothing
  in exchange.

### B. Build first, then approach
- ➕ "We built the thing your residents wanted, and here are the numbers" is a
  materially stronger opening.
- ➕ We would arrive holding the only measurement of their follow-through that
  exists, since their open-data portal publishes nothing on ábendingar.
- ➖ The repo is public in the meantime, so they may find it first.
- ➖ The ArcGIS finding stays unreported for as long as we wait.

### C. Split it — disclose the security finding now, pitch later
- ➕ Does not sit on someone else's exposure.
- ➖ Two approaches instead of one, and the first frames us as people who probe
  their systems.

## Decision

**Option B**, with the ArcGIS finding folded in rather than split out (#4, #6).

The trade-off is recorded rather than argued away: the window stays open for as
long as we wait, and this repo is public throughout. If the proof of concept
slips, split the disclosure out.

## Consequences

- The withdrawal of report 110474 is **not** this approach and must not become a
  pitch. It is an apology with a case number and nothing else.
- An information request (upplýsingabeiðni) under the Information Act
  (upplýsingalög) for historical response times is available independently and
  does not depend on the city's goodwill.
