# Borgarland Android POC — notes

A single-screen Android proof of concept for the citizen-report (ábending) app:
camera first, a coordinate the flow refuses to proceed without, category and
description chosen by a person, and the exact payload displayed. It posts to our
own relay, which is in dry run unless someone deliberately hands it a key, and it
has no way to reach the city.

Two sentences of this summary outlived the code. It said the coordinate comes
from EXIF with the device fix as a fallback, and that the app sends nothing and
structurally cannot. Neither is true, and the rest of this file was corrected in
#25 and #26 without the summary above it being reread.

## Build

```bash
./gradlew assembleDebug          # APK at app/build/outputs/apk/debug/app-debug.apk
./gradlew testDebugUnitTest      # 16 unit tests, all green
```

Verified green from a clean tree on this machine: JDK 25, Gradle 9.4.1 wrapper,
AGP 9.2.0, Kotlin 2.3.21, Compose BOM 2026.04.01, compileSdk 36, minSdk 26. All
versions mirror `rosaparks/gradle/libs.versions.toml` and its wrapper, because
that project demonstrably builds here. The only version the repo did not pin is
CameraX: 1.6.1, the latest stable on Google Maven at build time.

One gotcha worth recording, and it still applies: the package must be written
`` `is`.borgarland `` in Kotlin, because `is` is a hard keyword. It read
`is.borgarland.poc` until 2026-08-24, when the package was renamed before Play
could pin it (decision 0012); the backtick is a property of the `is` at the
front, so the rename changed the example and not the problem. Rosaparks
does the same (`` package `is`.rosaparks ``).

## The one rule, and how it is enforced

No capability to reach reykjavik.is or any city endpoint.

**This section described the POC before it could send anything, and the app has
moved past it.** The app now declares `INTERNET`, because it posts to our own
relay (decision 0002 says the apps post to the relay and never to the city).
What replaced "no network at all" is narrower and still checkable:

1. **No city endpoint anywhere in the app.** No hostname, no category slug, no
   path. `NoCityEndpointTest` asserts it on every build, scanning the source
   through `KotlinSource.stripComments`. That stripper has two jobs, and only
   one of them was obvious. It removes comments, so the rule can be documented
   in the file it governs. It also has to know what a **string literal** is: it
   used to cut each line at the first `//`, which turned
   `"https://reykjavik.is/…"` into `"https:` before the scan and let a city
   endpoint through the guard that exists to catch it — inside a string, which
   is the most likely place for one to be. Fixed in #71, with
   `KotlinSourceTest` covering both jobs.
2. **One relay URL**, from `BuildConfig.RELAY_BASE_URL`, per build type: the
   loopback for debug, `https://borgarland.samtak.is` for release (#29).
   `build.gradle.kts` refuses at configuration time to build a release whose URL
   is not https or names a loopback host.
3. **Cleartext to localhost only**, via `network_security_config.xml`. This does
   NOT need widening now that a real relay hostname exists, and an earlier
   version of this note said it did. The deployed relay is https, so the policy
   keeps doing its job: cleartext reaches the development machine and nothing
   else.
4. **`ACCESS_NETWORK_STATE` is still stripped** with `tools:node="remove"`,
   because nothing here reads connectivity.

Verified on the built artifact rather than the source: `aapt dump permissions`
on the APK lists `CAMERA`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` and
`INTERNET`, and no `ACCESS_NETWORK_STATE`.

`ACCESS_COARSE_LOCATION` is there on purpose and was added late, after Android
lint refused the build over it. Since Android 12 the permission dialog for a
FINE request carries an "Approximate" button, and an app that declared only FINE
is denied outright when the user presses it. Declaring both turns that press
into a coarse grant. Coarse cannot find a bin, so the app still asks for FINE
and the copy still says why; what this buys is a usable answer instead of a
refusal when someone gives less than we asked for.

`ACCESS_NETWORK_STATE` did appear in an intermediate build: CameraX 1.6.1
pulls `androidx.media3` (video muxing) whose manifest declares it. This POC
only captures stills and no code path reads connectivity, so it is stripped
with the same `tools:node="remove"` pattern and the provenance is commented in
the manifest.

## What the POC genuinely proves

1. **Opens on the camera.** Initial screen is a live CameraX preview; there is
   no path that starts with a form (decisions/0004).
2. **Both location sources, and the device one is what answers.** `ExifGps.kt`
   is a line-for-line port of `exifGps` in `scripts/send-report.mjs`: JPEG
   segment walk to APP1, TIFF endianness, GPS IFD via tag 0x8825, the four GPS
   tags, out-of-line rationals. No library. Six unit tests exercise it against
   hand-built JPEG buffers in both endiannesses and both hemispheres, plus the
   malformed-input cases that must read as "no GPS". The device source is the
   framework `LocationManager`, asking every enabled provider and taking
   whichever answers first, and the UI labels which one was used ("EXIF GPS úr
   mynd" vs "Tækjastaðsetning (GPS)").

   **On this POC the EXIF read always returns nothing**, because CameraX writes
   no GPS unless asked and nobody asks. So the device fix is the primary source
   here rather than the fallback the code reads like, and the EXIF reader is
   waiting for the gallery path that does not exist yet. `AGENTS.md` carries the
   corrected ordering, and `docs/research/photos-exif-and-formats.md` has the
   measurements behind it.
3. **The coordinate guard.** `isUsableCoordinate` rejects no-coordinate,
   non-finite values (which EXIF rationals with a zero denominator can
   produce) and out-of-WGS84-range values. The flow refuses to advance to the
   category screen without one, with a retry path. This is the rule the city
   does not enforce (`validation.onlyDescriptionIsEnforced` in the facts file).
4. **All twelve categories from the facts file.** `data/reykjavik-form.json`
   is shipped verbatim as an app asset and parsed with kotlinx-serialization.
   `type` is read per category from that file at runtime, never hardcoded, and
   used only as the picker's general/specific label (`almenn-abending` is
   `general`, the other eleven `specific`); `summary` is no longer read at all
   since the payload dropped the city's vocabulary. `FactsFileTest` asserts the
   asset parses to 12 categories with that exact split and the documented
   2500-character description limit. The suggestion slot sits above the picker
   and is empty in this POC; per decisions/0008 it may be late or absent and
   never blocks, and the flow completes without it.
5. **Description field** with the 2500-character limit enforced, taken from
   `fields.description.maxLength` in the facts file.
6. **Final screen shows every field that would be posted**: `category` (the
   slug), `latitude`, `longitude`, `description`, `photo` (name, MIME, byte
   size, thumbnail), plus the location source and a non-blocking warning when
   the point falls outside the city map widget's panning bounds (mirroring
   `send-report.mjs`). The request shape comes from `data/relay-request.json`
   (copied into assets like the facts file), and the screen states that the
   relay, not the city, is the only destination and that it is in dry run.

## What it fakes or stubs

- **The suggestion slot** is an empty placeholder card. No model produces
  suggestions; per decisions/0008 where the model runs is deliberately open.
- ~~**The relay** does not exist here~~ — it does. The worker landed in #22 and
  the app has posted to it since #23. What is still absent is the deployment:
  no D1 exists, nothing is deployed, and the relay is in dry run unless a key is
  deliberately supplied, so nothing has reached the city and follow-through is
  still unmeasured.
- **Reverse geocoding and the address registry** (iceaddr-ts) are not shipped.
  The city's payload has no address field anyway
  (`validation.noAddressFieldInPayload`), so the final screen is faithful
  without it.
- **Single photo.** The form accepts repeated files (`files` is repeated in
  the facts file); the POC captures one.
- **No email field**, though the facts file lists it as optional.
- ~~**Device fix is GPS-only**~~ — no longer true. Testing on a real phone
  indoors showed GPS never fixes under a roof, so a GPS-only request timed out
  and the report was refused while the network and fused providers held a
  three-minute-old fix accurate to eighteen metres. It now asks every enabled
  provider and takes whichever answers first.
- **No jurisdiction check** (SVFNR) **in the app**. AGENTS.md puts it in the
  relay, and the relay implements it (`worker/src/jurisdiction.ts`); the app has
  only the map-bounds warning. Nothing in this POC reaches a deployed relay, so
  in practice no coordinate has been jurisdiction-checked outside the worker's
  own tests.

## Places the repo did not say, so the POC guessed

- **CameraX version and capture mechanism.** The repo names no camera
  library; decisions/0008 leaves capture unspecified. Chose CameraX 1.6.1 with
  in-memory JPEG capture (no file storage, no FileProvider).
- **Device location API.** No location decision in the repo. Chose the
  framework `LocationManager` over play-services to keep dependencies minimal.
- **Category ordering.** decisions/0004 says ordering does the work the
  exclusion tried to do (season and recency first), but does not specify the
  algorithm. The POC shows the facts file's own order.
- **Suggestion slot visuals.** decisions/0008 specifies the contract (late or
  absent, never blocks), not the UI.
- **Description required in the UI.** `send-report.mjs` requires it and the
  facts file says the city enforces it, but the repo has no app-side
  validation spec. The POC gates the Continue button on a non-blank
  description.
- ~~**App name and package.** "Borgarland POC" and `is.borgarland.poc` are not
  specified anywhere.~~ Settled 2026-08-24, in two steps, and the first one
  claimed both. The package became `is.borgarland` before the first Play upload
  made it permanent (decision 0012). This entry then said "the name is
  Borgarland", which was **not true when it was written**: `android:label` and
  `CFBundleDisplayName` still read "Borgarland POC", on six installed phones,
  and the system permission dialog read it out loud — *"Allow Borgarland POC to
  access this device's location?"* Fixed in #135, a day later, after a device
  run put the sentence on screen. A rename covers a package or a label, never
  both by implication.
- **Location-source label wording** in Icelandic.
- **The facts file travels verbatim** as an asset, including the endpoint
  strings it carries as data. The app never reads the endpoint fields, and the
  permission strip plus the absence of any HTTP client make those strings
  inert. If that feels too loose for a future build, the asset can be trimmed
  to `categories`, `fields` and `map` at copy time.
- **UI language.** Icelandic, per AGENTS.md ("App UI strings are Icelandic"),
  with the English-first convention for code comments and docs.
