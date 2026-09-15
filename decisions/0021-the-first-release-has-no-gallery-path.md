# 0021 — The first release has no gallery path

- **Date:** 2026-09-15
- **Status:** Accepted

## Context

The app photographs a problem and files it. Every photograph it has ever sent,
it took itself: CameraX on Android, `AVCapturePhotoOutput` on iOS. There is no
way to file a picture that is already on the phone, and
`data/platform-parity.json` has carried that gap as `gallery-pick: neither-yet`
since 2026-08-23 — with the reason *"whether the first release has a gallery path
at all is an open decision"*, because there was no path to keep or remove, only
one to build (#28).

That reading is not obvious from the documentation. `AGENTS.md` discusses the
gallery at length, and `docs/research/photos-exif-and-formats.md` reasons about
picked files in detail, which reads as though the path exists. It does not.

Three things had already been settled around the edge of this question:

- **The capture path costs nothing.** iOS names its own codec per shot, so the
  app asks `AVCapturePhotoSettings` for JPEG and never converts a photograph it
  took itself. Verified on hardware: five photographs across two iPhones, every
  one reporting `mime image/jpeg`.
- **The relay refuses a declared MIME type that disagrees with the bytes**
  (`worker/src/image-format.ts`). A HEIC sent under an `image/jpeg` label is a
  rejection the person sees, not a photograph the city silently drops.
- **The work a gallery path needs is not a picker.** It is a picker per platform
  plus a filename and MIME derived from the actual bytes (Android hardcodes
  `mynd.jpg` and `image/jpeg` in `PocViewModel.kt:427`, which is true of
  everything CameraX produces and false the moment a file is chosen), a
  transcode with a quality somebody has to choose and write down, and reading
  EXIF out of the file bytes rather than a decoded image.

And the two failure modes are both measured rather than imagined. A picked HEIC
converted at quality 90 ran **larger** than the original, 4.14 MB to 4.78 MB,
against an upload ceiling that is still unknown — the 2026-08-30 submission
established 4.9 MB as a floor and nothing more. And `ExifGps.read` answers null
for anything that is not a JPEG, so a HEIC carrying a perfectly good coordinate
reads as having **no location at all** and falls through to the device fix: a
report pinned to wherever the phone happens to be standing, delivered
confidently.

The interaction this project actually validated is the other one. Decision 0004
makes the camera the entry point, with no flow that starts with a form; the
field-test record is a dozen walks where somebody stood in front of the thing
and photographed it. A picked photo is, by construction, not that case.

## Decision

**The first release is camera-only.** No gallery picker on either platform, on
either store, in the widget, or behind a flag.

The rule that decides it is the project's own scope test — *can a person walking
with a phone meet this thing and photograph it* — and a picture already on the
phone is not that interaction. Everything a gallery path needs is work whose
value depends on a need nobody has measured, and the two ways it can be wrong
are a size blow-up against an unknown ceiling and a location that is confidently
false.

`gallery-pick` stays `neither-yet` in `data/platform-parity.json`, with its
reason pointing here rather than calling the question open.

## Consequences

- **The question does not come back by accident.** A picker on either platform
  turns `platform-parity` red until the other side answers, which is the check
  doing exactly what it exists for: it forces a decision at the moment someone
  builds half of one.
- **The HEIC work is deferred, not solved**, and stays conditional in #28. The
  transcode, its quality, the size measurement against the ceiling, and reading
  EXIF from bytes are all unbuilt, and none of them is needed while a
  photograph is always one this app took.
- **The relay's MIME sniffing stays**, and it is what would make a future
  picker's mistakes loud rather than silent.
- **The location rule is untouched.** The coordinate still comes from the
  device at capture time and is still the only positional thing submitted. A
  gallery path would have introduced a second location source with a different
  failure mode, and that is a decision of its own — not a side effect of adding
  a button.
- **`docs/research/photos-exif-and-formats.md` keeps its gallery reasoning.**
  It is the measured reasoning behind this decision and the starting point if
  the answer ever changes; it is not a plan.

## Options that lost

**Build the picker on both platforms for the first release.** The honest version
of the ambitious option, and the one to revisit first if the answer ever
changes. Lost on need: it is the largest piece of unbuilt work in the app, and
nothing in the field-test record shows a walk where picking an existing
photograph was what the person wanted. The whole record is camera-first because
the app is.

**Build it on iOS only, where HEIC bites.** The cheapest-looking split, and it
is the wrong one. iOS is the platform where a picked photo's location is
weakest: a file read as a `UIImage` arrives with no EXIF at all unless the app
holds Photos authorization, so the path needs `loadFileRepresentation` to be
correct at all. Adding it to one platform also turns `platform-parity` red by
design, so this is not a split — it is a decision to do the work twice, later.

**Build it, and refuse a picked photo whose EXIF carries no coordinate.** The
most defensible version of the feature: it is honest at the point of refusal,
and it matches the rule the relay already applies to a coordinate it cannot
trust. Lost on cost for a need that is unmeasured — the picker, the byte-derived
MIME, the transcode and the EXIF-from-bytes read are all still required, and the
refusal it buys is a worse experience than never offering the button, because
the person has already chosen the photograph by the time they are told.

**Receive a photograph through the share sheet or an Android intent filter.**
Same work as the picker, and it starts the flow outside the app, which is
exactly the shape the camera-entry-point rule exists to prevent.

**Leave it undecided.** What the parity file said until now, and the reason this
record exists. "Open" reads as "somebody should build this" to whoever arrives
next, and the documentation already reads that way; a decision that says no is
more useful than a status that says nothing.

## What would change this

A person who had a photograph of the thing already and would not walk back to
take another — which is a question for the next tester conversation, and costs a
message rather than a feature. If it is ever answered that way, the path needs
its own decision about which location source it trusts and what it does when the
photograph has none, because the coordinate is not a detail here; it is the one
thing this app insists on that the city's own form does not.
