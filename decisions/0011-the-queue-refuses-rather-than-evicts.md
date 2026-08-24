# 0011 — The offline queue refuses rather than evicts

- **Date:** 2026-08-23
- **Status:** Accepted

## Context

#73 put a queue in front of the send: a report is written to the phone before
the attempt, because the failure it guards against arrives *after* the decision
to send. A report leaves the queue when it is sent, when the relay refuses it,
when a person discards it, and when its photograph has gone missing and it can
no longer be built.

Nothing else removed one, so a phone that never came back online kept every
report ever filed on it, at a photograph each — 0.24 MB to 2.29 MB apiece across
the two field tests. That is unbounded storage on somebody's phone, taken
without asking (#82).

The awkward part is that **every way of bounding a queue loses something
somebody filed.** This is not a tuning problem with a right answer; it is a
choice about who pays.

## Considered options

### A. Oldest-first eviction
- ➕ The obvious one, and the new report always fits.
- ➖ Throws away the report that has waited longest, which is the one most likely
  to matter and the one whose owner has waited most for it.
- ➖ Silent. Nobody is told, and the queue looks like one that works.

### B. An age limit
- ➕ Bounded without a count, and stale data does decay in value.
- ➖ Discards a report from a walk somebody still remembers taking.
- ➖ Silent in the same way, and the deletion happens when nobody is looking.

### C. Refuse the new report, and say so
- ➕ Nothing that was filed is ever thrown away by the app.
- ➕ The failure lands in front of the one person who can act on it, at the
  moment they are standing there: send what is waiting, or discard something on
  purpose.
- ➖ The person cannot file the thing in front of them until they deal with it.
- ➖ Needs a sentence in the interface, so it is not free.

## Decision

**C.** `ReportQueue.enqueue` throws when the queue is full and the report is not
written down. The app says so and does **not** fall back to sending unqueued: a
send that cannot be retried is how the report was lost in the first place.

**Twenty reports or 200 MB, whichever is reached first.** Twenty is a number
about walks rather than about storage — a person reaches it only by filing
report after report with no network at all, and by the twentieth something is
wrong that more disk will not fix. The field tests filed one and two. The byte
bound is roughly a hundred photographs at the sizes those tests measured.

Nothing leaves the queue without somebody choosing it. That is the property, and
the numbers are in service of it.

## Consequences

- Both bounds are injectable, so tests reach them with two four-kilobyte
  photographs rather than 200 MB of real ones, and one test asserts the app
  takes the documented numbers.
- A half-written entry is removed on the failure path. Photo bytes in a
  directory with no readable record are invisible to the listing, uncounted by
  the byte bound and removable by nothing — a leak of one photograph per failure
  on exactly the disk-pressure path `enqueue` throws for.
- The record format is read with defaults rather than requirements. A required
  key on a persisted record is a silent eviction of a different kind: the record
  fails to decode, the listing skips unreadable entries by design, and the report
  disappears with nobody choosing it.
- iOS only, because the queue is. `data/platform-parity.json` records that with
  its reason (#58, #2).

## References

- #82, #73; PRs #96 and #99
- `ios/BorgarlandCore/Sources/BorgarlandCore/ReportQueue.swift`
- [`data/platform-parity.json`](../data/platform-parity.json), `offline-queue`
