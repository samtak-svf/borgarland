# Location and photo formats

> Moved verbatim from the root `AGENTS.md` (agent-config#1482 step 4), where the rule stays as one line under the heading **The location comes from the device at capture, not from an address**. Read this on the trigger named in the root's "Rule detail" table.

The city's form leads with "Sláðu inn heimilisfang". That is the wrong primitive
here. As Biggi put it when the idea started: *the bin has no address, only the
coordinate that came with the photo.* The coordinate is obtained from the
device, at the moment the photo is taken, rather than from the picture as that
wording suggests — while the principle the quote states, that an address is the
wrong primitive, is exactly what held up. Three things must stay distinct. The GPS
point comes from the device at capture time, and it is the only positional thing
submitted to the city. The nearest registered address is a reverse lookup in the
relay, appended to the description as a block for the crew — with the coordinate
it was looked up from and how far away it was, so neither can be read as the
other. It is not the location, and a report is never snapped to it (see
[Addresses](../../worker/AGENTS.md)). EXIF is relevant only to
a photo picked from the gallery, and there is no such path: decision 0021 keeps
the first release camera-only (`gallery-pick` stays `neither-yet` in
`data/platform-parity.json`). A map would be a correction rather than an entry
point. (No map exists in either app yet; the sentence describes the intended
shape, not a built surface.)

**Which source comes first depends on where the photo came from, and testing on
a real phone reversed the order we assumed.** A photo the app captures itself
carries no EXIF GPS at all, because CameraX does not write it unless asked, so
the device fix is the primary source on that path and not the fallback. EXIF is
the primary source for a photo chosen from the gallery — which is also the path
where it is most often missing, since messaging apps strip it. Ask both, label
which one answered, and refuse when neither does.

**The city accepts `image/jpeg`, `image/png` and `image/gif`, and an iPhone
shoots HEIC.** On our own capture path that is a setting, not a constraint: iOS
names its own codec through `AVCapturePhotoSettings`, so ask for JPEG and never
transcode a photograph we took ourselves. The gallery is where it bites, on both
platforms. A picked HEIC has to be converted, and conversion runs *larger* than
the original (4.14 MB became 4.78 MB at quality 90); `ExifGps.read` understands
only JPEG and reads a HEIC as having no location at all; and on iOS a picked
photo read as a `UIImage` arrives with its EXIF gone, so read the file bytes
instead. **All of this is reasoning about a path nobody has built**: decision
0021 keeps the first release camera-only, so it is the measured starting point
if a picker is ever added rather than a description of one. Measured against a
real original, along with what else the GPS block carries and the reverse lookup
running end to end:
[docs/research/photos-exif-and-formats.md](../../docs/research/photos-exif-and-formats.md).
