# 0019 — A capability ships when Android is device-verified and iOS is CI-green

- **Date:** 2026-08-31
- **Status:** Accepted

## Context

The refused-permission box in #179 made the platform asymmetry concrete
instead of invisible. The gallery save's Android refused-state can only
exist on API 26–28, and the handset on the cable is API 33 — measured:
`adb shell pm list permissions` on the A71 returns zero matches for
WRITE_EXTERNAL_STORAGE, because the permission stopped existing after
API 28. So the Android refused state is unreachable on the device in the
room, however long it stays connected. The iOS half needs a handset, and
no iPhone is on a cable. Both halves are implemented and unit-tested; the
unchecked acceptance boxes are real.

That this is a **position** rather than an oversight was settled by
Guðröður: iOS verification lags Android, by design. This record makes the
position durable and names what it costs, so a future session reads a
standing rule instead of re-deriving it from an unchecked box.

## Decision

**A capability is done when Android is device-verified and iOS is
CI-green** (build + BorgarlandCore tests + XCUITest on the hosted
macOS runners), with the iOS device walk a separately tracked follow-up
rather than a blocker on the ship. An issue closes on that state; the iOS
walk is tracked explicitly, never inferred from the absence of a box.

Two facts make the position cheap to hold rather than merely convenient:

- **The machine has no iOS at all.** No Mac, no local Swift compiler, no
  iPhone — CI is the only verification that exists for the iOS half, so
  "CI-green" is not a lowered bar, it is the only bar present. The repo
  has done iOS device work without buying hardware, on a rented device
  (#126), and #188 tracks the Mac handshake that unblocks iPhone
  screenshots — so the follow-up is a known path, not a discovery.
- **Android device verification is the walk that finds the real
  defects.** The A71 walk on 2026-08-31 found the pre-migration 500, the
  gallery byte-count match, and the session join — the class of defect a
  compile cannot see. Blocking every ship on an iOS device that is not in
  the room would serialize every feature on a hardware dependency.

## Consequences

- **Issues close with Android-verified + iOS-CI-green.** The acceptance
  box is the contract; this decision is the standing interpretation of
  what "verified" means per platform, and it must be stated in the issue
  rather than assumed (as #179 now does, with the two halves split).
- **The iOS walk is a tracked step, not a silence.** When the follow-up
  happens, it is the rented-device path (#126) or the device the Mac
  handshake (#188) unblocks.
- **The cost is accepted, not hidden.** An iOS-only defect that only a
  device shows can ship. That is the price of the position, and the
  mitigation is CI-green plus the tracked walk — not a promise that the
  class cannot occur.

## Options that lost

**Block every ship on iOS device verification.** Serializes every feature
on a hardware dependency that has no machine in the room; the gallery
save and everything after it would wait indefinitely. Rejected because
the walk-level verification that exists (Android) is the one that finds
the real defects.

**Ship on CI-green alone, without Android device verification.** The
Android walk is the cheapest, present verification and the one that has
found every real walk-level defect so far (the pre-migration 500, the
byte-count match, the session join). Dropping it to equalize the
platforms would remove the stronger instrument, not add the weaker one.
Rejected.

**Buy an iPhone for the machine.** Hardware purchase for a verification
that has a working rented-device precedent (#126); rejected as
unnecessary until the follow-up actually needs a device in the room.
