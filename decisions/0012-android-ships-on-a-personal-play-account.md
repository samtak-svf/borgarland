# 0012 — Android ships, on a personal Play account and not the party's

- **Date:** 2026-08-24
- **Status:** Accepted

## Context

Until today the two apps were not at the same stage and it was easy to read them
as though they were. iOS had a signed release workflow, a TestFlight group,
Crashlytics and a build in a stranger's hand. Android had a working app that
could not leave this machine: no signing config, no keystore, no release
workflow, no crash reporting. #58 named that gap and said the decision behind it
was genuinely open — *"Android stays a development POC until there is an Android
tester"* was a legitimate answer.

Two things had changed since #58 was written, and both argue against that answer.

The issue assumed the field testing was iOS-only, because Biggi and Jökull are
both on iPhones. **Four Android field sessions have happened since**, all on real
phones, two of them on 2026-08-24 alone
([`data/field-tests.json`](../data/field-tests.json)). Android is not untested.
It is undelivered.

And every one of those sessions paid the same toll. The relay host is a
`buildConfigField`, so only a **release** build carries the deployed host — which
meant building release, then `zipalign`, then `apksigner` with a debug keystore,
then `adb install`, by hand, every time. That is not a hypothetical cost. It is
the cost that was being paid, silently, on each test.

## Decision

**Android ships.** Signing config, a release workflow modelled on
`ios-release.yml`, Crashlytics on the existing `borgarland-app` Firebase project,
and Play internal testing.

**On Guðröður's personal Play Console developer account, not the party's.**

**The package is `is.borgarland`, not `is.borgarland.poc`.**

## Why a personal Play account

The house pattern (`~/.claude/skills/sosi-android-app-delivery`) puts every
Android app on the Sósíalistaflokkurinn developer account
`5400094003987166957`. Borgarland is a Samtak svf. app, and Rósa Parks being
stuck on that same party account is an **open severance item** — rosa-parks#277,
tracked in the severance ledger rosa-parks#268. Publishing a second co-op app
there would deepen an entanglement that is actively being unwound.

The personal account costs nothing, waits for nothing, and belongs to no party.
It is not the end state: a Samtak svf. developer account is the clean answer, and
this decision does not foreclose it. It declines to make the party's account the
default a third time.

## Why the package was renamed first

`applicationId` was `is.borgarland.poc` while iOS was `is.borgarland`. **Play pins
the package name for the life of the app** — after the first upload it cannot be
changed, and a different package is a different listing with no installs and no
reviews. The rename cost one line and a mechanical move of thirty files today. It
would have cost the listing tomorrow.

This is the same class as the `versionName = "0.1.0-rp"` near-miss: a
dev-internal placeholder about to become a permanent user-visible label. Caught
before the action, which is the only time catching it is worth anything.

## Options considered

**A signed APK on a GitHub release, no store.** Genuinely attractive: it removes
the hand-signing toll and commits to nothing. Rejected because it delivers to
people who can sideload, which is a smaller set than the people we want to hand
this to, and because the Play account question would only have been deferred.

**The party Play account.** The path of least resistance and the documented house
pattern. Rejected above.

**A new Samtak svf. developer account.** The cleanest answer and probably the
eventual one. Rejected *for now* on a registration wait and a $25 fee for an app
with no testers yet. Revisit when Rósa Parks moves.

**Stay a development POC.** The answer #58 itself offered. Rejected because four
hardware sessions have already happened and each paid a manual toll; the app is
being field-tested whether or not it is delivered.

## Consequences

**Two deliberate divergences from the delivery skill**, both recorded here rather
than left to be discovered:

1. **Signing material comes from GitHub secrets, not Workload Identity
   Federation.** The skill's rule exists for apps on the party account with a WIF
   pool already standing; this app has neither, and this repository *already*
   signs iOS from GitHub secrets. A second auth mechanism would be a fork for its
   own sake. The keystore is backed up in Secret Manager as
   `borgarland-android-upload-*` in `fedora-setup-secrets`.

2. **R8 stays off.** The skill's Gradle block sets `isMinifyEnabled = true`.
   Turning on minification in the same change that adds Firebase is exactly what
   shipped Símaver `0.1.0-beta35` to 26 testers with a crash on every launch — R8
   strips the Crashlytics `ComponentRegistrar`, the build succeeds, and only a
   real launch shows it. With minify off, Crashlytics needs no keep rules and no
   mapping upload. Turning it on is #118, with its own device smoke test.

**The upload key cannot be rotated once Play pins it.** It exists in two places
and must stay in both: `fedora-setup-secrets` and the GitHub secret. This
repository is public, so `android/app/*.p12` and `android/app/keystore.properties`
were added to `.gitignore` *before* the key was generated.

**The release workflow verifies the fingerprint** (`apksigner verify
--print-certs` against a pinned SHA-256) so a wrong key fails the build rather
than producing an artifact nobody can ever update.

`data/platform-parity.json` moves `crash-reporting` and `signed-release-pipeline`
off `ios-only`, and #2's CI criterion is satisfied rather than rewritten.
