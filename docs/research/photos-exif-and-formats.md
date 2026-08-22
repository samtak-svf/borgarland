# What a real photograph actually carries

Established 2026-08-22 from a single original file: `IMG_9498.HEIC`, an iPhone 13
photograph of an overflowing waste bin (ruslafata) taken 2026-08-21 at 18:51:41.
It is the original of the picture used to test photo analysis in
[decision 0008](../../decisions/0008-photo-analysis-suggests-never-decides.md) —
that test used a copy that had been through a messaging app, and the difference
between the two files is most of this document.

Nothing here was sent anywhere. Reading a file cannot file a report.

## The original carries a coordinate, and a copy of it does not

| | the original | the copy used in the 0008 test |
|---|---|---|
| Format | HEIC, 4,144,780 bytes | JPEG, 99,172 bytes |
| Pixels | 4032 × 3024 | 1536 × 2048 |
| EXIF | Make, Model, three timestamps, lens, orientation, MakerNote | none at all |
| GPS | 64.125206, −21.855372 | none |

Same bin, same dog, same afternoon. One file can locate itself and the other
cannot, and nothing in either file says which kind you are holding.

This is the concrete form of the rule in `AGENTS.md`: EXIF is the primary source
on the gallery path *and* the path where it is most often missing. A photograph
that has passed through a chat app arrives stripped and downscaled, and it looks
like a perfectly ordinary photograph while doing so.

## The GPS block holds more than a coordinate

```
GPSLatitude            64 deg  7' 30.74" North
GPSLongitude           21 deg 51' 19.34" West
GPSAltitude            28.3 m above sea level
GPSImgDirection        135.981° true
GPSDestBearing         135.981° true
GPSHPositioningError   3.53553 m
GPSSpeed               0 km/h
GPSTimeStamp           18:51:40
GPSDateStamp           2026:08:21
```

Two of these are worth more than the coordinate on its own.

`GPSHPositioningError` is the accuracy of the fix in metres, written by the
phone. Today `PocViewModel` accepts any EXIF coordinate that passes the
finiteness and WGS84 range guard, with no idea whether it is a 3-metre fix or a
3-kilometre one. The device-fix path already reasons about accuracy
(`DeviceFix.kt`); the EXIF path has the same information available and ignores
it.

`GPSImgDirection` is which way the camera was pointing. The coordinate says
where the reporter stood, not where the bin is. For anything photographed from
across a street that is a real difference, and the bearing is the only thing in
the file that could close it.

`GPSSpeed` is 0 km/h, which says the phone was standing still. A fix taken at
walking pace is a different quality of fix from one taken at a stop, and this is
the file saying which it was.

Both bearing and accuracy are also disclosures, and belong in the privacy policy
(#5) alongside the coordinate rather than being quietly along for the ride.

## The coordinate is where the reporter stood, not where the thing is

Worth stating separately because it changes what the three fields are *for*.
Reading them together on this one photograph:

| | value |
|---|---|
| Point (WGS84) | 64.125206, −21.855372 |
| Point (ISN93 / EPSG:3057) | 360950.2, 405618.1 |
| Stated accuracy | 3.54 m radius |
| Camera bearing | 135.98° true (138.41° grid, meridian convergence 2.43°) |
| Nearest registered address | Rauðagerði 43, 22 m |

Laid over the 2025 orthophoto (map.is, Loftmyndir ehf.) at 0.0625 m/px, two
objects sit inside the accuracy circle. Offsets measured off the screen, so
call them ±0.5 m:

- a bench, about 2.9 m due north of the point;
- a compact object about 1.8 m away at roughly 72° true, standing on the paving
  and casting a shadow in the same direction as everything else in the frame.
  Right size and place for the bin in the photograph.

**The bearing and the point disagree by 62°, and the accuracy is what settles
it.** The camera faced 136°; the candidate object lies at 72°. Shift the true
camera position about 3 m north-west, which is well inside the 3.54 m the phone
itself declared, and the object falls on the axis. The three fields are not in
conflict; they are only in conflict if you read the coordinate as exact.

So the useful reading is not "the report is at this point". It is **a cone**:
apex somewhere within the accuracy radius, opening along the bearing. That
locates the object rather than the photographer, and the difference is the whole
distance between a crew finding a bin and a crew standing where someone once
stood.

Two honest limits. The orthophoto is from 2025 and the photograph from 2026, so
the object match is strong but not proof. And the photograph was taken in flat,
overcast light with no usable shadow of its own, so the bearing could not be
checked against the sun; it is taken on the phone's word.

What this could be worth in the interface is open — see #31. Nothing is built on
it yet, and nothing should be until the design says what it is for.

## The city does not accept the format an iPhone produces

`data/reykjavik-form.json` records the form's accepted types: `image/jpeg`,
`image/png`, `image/gif`. HEIC is not among them, and HEIC is what an iPhone
shoots by default.

**On our own capture path that default is ours to override, and this section
first said otherwise.** The HEIC default belongs to Apple's Camera app and the
Settings → Camera → Formats toggle; it does not govern a third-party app.
An app driving `AVCapturePhotoOutput` names its own codec per shot:

```swift
if photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
    settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
}
```

So the iOS app should ask for JPEG at capture and never transcode its own
photograph at all. (Established from Apple's AVCam sample and WWDC 2017 session
511, *Working with HEIF and HEVC*, not from a compiled test — nothing here can
build Swift.)

The one caveat carries over from Android: capturing JPEG does not give us a
coordinate. AVFoundation writes no GPS unless the app attaches it through
`AVCapturePhotoSettings.metadata`, exactly as CameraX writes none unless asked.
The device fix stays the primary source on the capture path on both platforms.

**Where the format genuinely is not ours is the gallery**, which is the reverse
of what this document originally claimed. A picked file is whatever the phone
stored, usually HEIC, and there conversion is unavoidable. Transcoding is not
free, and it does not go the direction you would guess:

| | bytes |
|---|---|
| Original HEIC | 4,144,780 |
| JPEG, quality 90 | 4,781,081 |
| JPEG, quality 80 | 3,298,935 |

A faithful conversion is **15 % larger than the original**. Against the unknown
upload limit, the Android measurements (1.1 MB and 2.66 MB) made 8 MB look like
a three-photo ceiling; two iPhone photos at quality 90 pass it. The transcode
quality is therefore a decision with a consequence, not a default to inherit.

The iOS gallery path has a second trap in the same place. Reading a picked photo
as a `UIImage` loses the metadata: with no Photo Library authorization the picker
hands back an image with no EXIF and no asset identifier, which would silently
cost us the coordinate on exactly the path where EXIF is the primary source.
The fix is to take the **file**, not the image — `itemProvider.loadFileRepresentation`
returns the original bytes with EXIF intact and needs no Photos permission, which
is also Apple's own recommendation on the developer forums over configuring the
picker with a `PHPhotoLibrary`. Read the coordinate out of those bytes, the same
way Android reads it.

Android has the mirror of this problem waiting. `PocViewModel.onPhotoCaptured`
hardcodes `name = "mynd.jpg"` and `mime = "image/jpeg"`, which is true for
everything CameraX produces and becomes false the moment a gallery picker lands
in #2 — Android holds HEIC too. And `ExifGps.read` returns null for anything
that does not start with the JPEG SOI marker, so a HEIC with a perfectly good
coordinate reads as *no location* and falls through to the device fix. On the
gallery path the device is not where the photo was taken, so that fallback is
not a degradation, it is a wrong answer delivered confidently.

None of this is live today: the POC has no gallery path and CameraX writes
JPEG. It is a list of things that must be true before #2 gains a picker and
before #3 exists at all.

## The location chain, proven end to end on one file

The coordinate out of the EXIF was run through the same reverse lookup the relay
performs, against the live national registry (Staðfangaskrá) via `iceaddr-ts` —
the same source and parser as `worker/scripts/refresh-registry.mjs`, which
touches no city endpoint:

```
point            64.125206, -21.855372
registry rows    139,360 with coordinates
nearest          Rauðagerði 43, 108 Reykjavík — 22 m away
SVFNR            0  → Reykjavíkurborg
jurisdiction     passes
```

Twenty-two metres is the useful number. The bin has no address, exactly as the
project's premise says; the nearest registered one is close enough to put in the
description so a crew can find it, and far enough that snapping the report to it
would be a lie about where the bin is.

That is the whole location argument working once, on a real photograph, without
a single request to the city.

## How to repeat it

```bash
exiv2 -pa IMG_9498.HEIC | grep -i gps
heif-convert -q 90 IMG_9498.HEIC out.jpg
```

The reverse lookup is `streamStadfangaskra` and `haversineKm` from `iceaddr-ts`,
taking the minimum by great-circle distance — `worker/src/registry.ts` does the
same thing over the D1 rows.
