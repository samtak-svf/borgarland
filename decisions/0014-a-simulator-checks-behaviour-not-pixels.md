# 0014 — A simulator checks behaviour, not pixels

- **Date:** 2026-08-27
- **Status:** Accepted

## Context

Nothing verified iOS behaviour before it reached a tester's phone. `ios-ci.yml`
compiled and `ios-core` ran the package's unit tests; neither launched the app.
There is no Mac on this machine, so there was no local simulator and no way to
look at a screen before a build went to TestFlight.

The cost is measured rather than hypothetical. Every iOS defect this project has
found came from a person holding a phone: #73, #74, #76, #77, #78 and #79 from
one field test, #85 and #86 from another. The loop is a signed build, an upload,
App Store processing and somebody's evening.

#110 is the clearest case. A keyboard covering a submit button compiles
perfectly, passes every unit test, and was in screenshots already captured while
an agent read accessibility trees and blamed its own taps.

`macos-latest` runners can run the iOS Simulator, this repository already builds
on them, and its minutes are free because it is public. So the machine was
always there. #125 asked which kind of test to put on it, and specifically
whether **snapshot tests** are in scope, because they need committed reference
images and a policy for updating them.

## Considered options

### A. XCUITest only — drive the app and assert behaviour
- ➕ Catches exactly #110's shape: a control that exists and is not reachable.
  `isHittable` answers that question and nothing else here does.
- ➕ No committed binaries, so nothing to keep in step with a design.
- ➕ Fails for a reason a person can read: a named control was not hittable.
- ➖ Slower than a unit test and can flake, most often on the simulator keyboard.
- ➖ Sees nothing about colour, spacing or type.

### B. Snapshot tests — render a view and diff against a committed image
- ➕ Catches a layout regression nobody thought to assert about.
- ➕ Fast, and no simulator interaction to flake.
- ➖ **The reference images are the specification, and nobody reviews an image
  diff honestly.** The update path is "re-record", which is one keystroke away
  from accepting the regression.
- ➖ They are device, OS and font specific. A runner image bump changes the
  rendering, every reference fails at once, and the only practical response is
  to re-record all of them — which is indistinguishable from a real regression
  being accepted in bulk.
- ➖ Committed binaries in a public repository, growing per screen per device.
- ➖ This app's screens are still moving weekly.

### C. Both
- ➕ Widest coverage.
- ➖ Pays B's costs for a project whose known defect class is entirely A's.

## Decision

**A. XCUITest on a simulator, in a `uitest` job in `ios-ci.yml`. Snapshot tests
are out of scope, and this record is the "decided and recorded" #125 asked for.**

The deciding argument is not that snapshots are bad. It is that **a check whose
failure mode is "re-record the reference" is a check that decays into an
approval**, and this repository's whole practice is the opposite: a guard that
can go vacuous is treated as worse than no guard, which is why
`worker/tests/outcomes.test.ts` scans the Worker's own source for codes it might
have missed and why `NoCityEndpointTest` strips comments before it looks.

Every iOS defect on the record so far is a behaviour: a button that could not be
reached, a permission that could not be recovered from, a report that vanished.
None of them is a pixel.

## Consequences

- `ios/project.yml` gains a `BorgarlandUITests` target and an explicit
  `Borgarland` scheme. The scheme has to be declared: `xcodebuild test` needs
  the UI bundle in the scheme's test action, and an autocreated scheme is not
  shared, so CI cannot see it.
- `ReportModel` gains a `-uiTestDetailsScreen` launch argument under `#if DEBUG`.
  The app opens on the camera and a simulator has no camera, so without a seam
  every screen past the first is unreachable. Release builds do not compile it.
- Two accessibility identifiers exist for the tests to query by, because a
  SwiftUI `TextField(axis: .vertical)` is a text view to XCUITest on some iOS
  versions and a text field on others.
- **This does not replace a phone in a hand.** `data/field-tests.json` exists
  because the two find different things, and the defects in that file are the
  ones no test and no CI run can see. This is about not spending a tester's
  evening on the cheap ones.
- If snapshot tests are ever reconsidered, the thing to fix first is the update
  path, not the library.

## References

- #125, and #110/#111 — the Android defect of the same shape
- `.github/workflows/ios-ci.yml`, `ios/UITests/DetailsKeyboardTest.swift`
- [decision 0001](0001-record-facts-reasoning-and-decisions-separately.md)
