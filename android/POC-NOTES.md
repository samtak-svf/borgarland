# Borgarland Android POC — notes

A single-screen Android proof of concept for the citizen-report (ábending) app:
camera first, coordinate from the photo's EXIF GPS with a device-fix fallback,
category and description chosen by a person, and the exact payload displayed.
It sends nothing, and structurally cannot.

## Build

```bash
./gradlew assembleDebug          # APK at app/build/outputs/apk/debug/app-debug.apk
./gradlew testDebugUnitTest      # 10 unit tests, all green
```

Verified green from a clean tree on this machine: JDK 25, Gradle 9.4.1 wrapper,
AGP 9.2.0, Kotlin 2.3.21, Compose BOM 2026.04.01, compileSdk 36, minSdk 26. All
versions mirror `rosaparks/gradle/libs.versions.toml` and its wrapper, because
that project demonstrably builds here. The only version the repo did not pin is
CameraX: 1.6.1, the latest stable on Google Maven at build time.

One gotcha worth recording: the package `is.borgarland.poc` must be written
`` `is`.borgarland.poc `` in Kotlin, because `is` is a hard keyword. Rosaparks
does the same (`` package `is`.rosaparks ``).

## The one rule, and how it is enforced

No capability to reach reykjavik.is or any city endpoint. Three layers:

1. **No INTERNET permission** is declared in the manifest, and
   `tools:node="remove"` strips it from the merged manifest even if a library
   declares it.
2. **No HTTP client, no networking dependency.** The dependency set is
   compose/material3, lifecycle, activity, kotlinx-serialization, CameraX and
   the framework `LocationManager`. Nothing on the classpath can make an HTTP
   request (verified via the runtime dependency graph).
3. **The send step does not exist.** The flow ends at a screen that displays
   the exact payload. There is no endpoint URL in any code path and nothing to
   call one with.

Verified on the built artifact, not just the source: `aapt dump permissions`
on `app-debug.apk` lists only `CAMERA` and `ACCESS_FINE_LOCATION` (plus the
app's own internal dynamic-receiver guard permission). Zero
`INTERNET`, zero `ACCESS_NETWORK_STATE`.

`ACCESS_NETWORK_STATE` did appear in an intermediate build: CameraX 1.6.1
pulls `androidx.media3` (video muxing) whose manifest declares it. This POC
only captures stills and no code path reads connectivity, so it is stripped
with the same `tools:node="remove"` pattern and the provenance is commented in
the manifest.

## What the POC genuinely proves

1. **Opens on the camera.** Initial screen is a live CameraX preview; there is
   no path that starts with a form (decisions/0004).
2. **EXIF GPS read, ported not imported.** `ExifGps.kt` is a line-for-line port
   of `exifGps` in `scripts/send-report.mjs`: JPEG segment walk to APP1, TIFF
   endianness, GPS IFD via tag 0x8825, the four GPS tags, out-of-line
   rationals. No library. Six unit tests exercise it against hand-built JPEG
   buffers in both endiannesses and both hemispheres, plus the malformed-input
   cases that must read as "no GPS". Device fallback via framework
   `LocationManager` (last-known GPS fix, then a single live request with a
   15 s timeout), and the UI labels which source was used ("EXIF GPS úr mynd"
   vs "Tækjastaðsetning (GPS)").
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
- **The relay** (decisions/0002 option B) does not exist here, by design: the
  POC ends at the payload display, so there is no worker, no D1, and nothing
  to measure follow-through with.
- **Reverse geocoding and the address registry** (iceaddr-ts) are not shipped.
  The city's payload has no address field anyway
  (`validation.noAddressFieldInPayload`), so the final screen is faithful
  without it.
- **Single photo.** The form accepts repeated files (`files` is repeated in
  the facts file); the POC captures one.
- **No email field**, though the facts file lists it as optional.
- **Device fix is GPS-only** (framework `LocationManager`); no network
  provider, deliberately, to keep the permission surface to one location
  permission.
- **No jurisdiction check** (SVFNR). AGENTS.md puts that in the relay, not the
  app, and there is no relay here. The map-bounds warning is the only
  geo-sanity signal.

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
- **App name and package.** "Borgarland POC" and `is.borgarland.poc` are not
  specified anywhere.
- **Location-source label wording** in Icelandic.
- **The facts file travels verbatim** as an asset, including the endpoint
  strings it carries as data. The app never reads the endpoint fields, and the
  permission strip plus the absence of any HTTP client make those strings
  inert. If that feels too loose for a future build, the asset can be trimmed
  to `categories`, `fields` and `map` at copy time.
- **UI language.** Icelandic, per AGENTS.md ("App UI strings are Icelandic"),
  with the English-first convention for code comments and docs.
