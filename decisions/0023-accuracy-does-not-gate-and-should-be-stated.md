# 0023 — The fix's accuracy does not gate a report, and the crew should be told when it is loose

- **Date:** 2026-09-15
- **Status:** Accepted

## Context

A photograph carries three location fields and a device fix carries more than
one. The project reads one of them (#31):

- `GPSHPositioningError` — how wrong the fix might be, in metres, written by the
  phone itself; the platform equivalent is `Location.getAccuracy()` on Android
  and `CLLocation.horizontalAccuracy` on iOS.
- `GPSImgDirection` — which way the camera faced.
- `GPSSpeed` — whether the phone was standing still when the fix was taken.

**What the code does today, read rather than remembered.** Both EXIF readers
take exactly the coordinate and nothing else: `ExifGps.swift` in
`BorgarlandCore` reads latitude, longitude and the two hemisphere references and
says so in its own comment, and `ExifGps.kt` on Android "pulls the four tags".
Neither reads accuracy, bearing or speed.

The **device** path, which is the primary source on the capture path, does
measure accuracy: `PocViewModel.kt:558` sends `location.accuracy.roundToInt()`
as the telemetry event's `accuracyM`, and iOS's `locationResolved` carries the
same. It stops there. `data/relay-request.json` names eight fields and none of
them is accuracy, and `accuracy` appears in **no** migration — the reports table
has no such column.

So the number exists on the phone, travels to our own event stream, and never
reaches the city or the crew.

**The measurement that makes this live.** The one real report, reference 110759,
was filed with `accuracyM: 100` — the coarsest fix in the whole field-test
record, and four times worse than the abandoned attempt's 39 five minutes
earlier at the same place. The city accepted it, because neither the city nor
the relay looks at accuracy. And since decision 0020 the relay appends a
distance rounded to **ten metres** to the description the crew reads. On that
report, the sentence claims a precision the fix does not have.

## Decision

**1. Nothing gates the report on a fix's accuracy.** It is filed whatever the
number is. The city enforces nothing on the coordinate, so a gate would refuse
only *our* reports; the one sample the project has is a 100 m fix that the city
acted on; and no threshold can be supported by a single observation. A gate would
also need a screen explaining the refusal and something for the person to do
about it, in the middle of the walking interaction decision 0004 governs.

**2. Bearing is not read.** `GPSImgDirection` is the direction the camera faced,
which on its own is a ray from the photographer with no length. Turning it into
"about 20 m south-east of Rauðagerði 43" — the form #31 suggests a crew could act
on — needs a distance EXIF does not carry, and estimating one from focus or
subject size is a research project #31 itself puts out of scope. Reading a field
we cannot act on would also be a disclosure with no purpose behind it.

**3. The accuracy should travel, and be said beside the distance.** The defect
worth fixing is not that accuracy is ungated; it is that a crew is shown a
ten-metre distance with no way to know the fix behind it may be a hundred metres
out. Carrying the fix's accuracy on the report and stating it in the composed
block fixes that. It is a wire change — a new optional part in
`data/relay-request.json`, which the relay must be deployed with **before** any
build sends it, plus a column, both apps, and then the wording — so it is filed
as **#223** rather than done here. Nothing about what the city receives changes
today.

**4. What is read from EXIF beyond the coordinate is nothing.** There is
therefore nothing to disclose from the EXIF path, and that is stated rather than
left as an open question. The accuracy that does travel today is in the event
stream, whose allowlist is documented as carrying no free text, no coordinate and
no personal data. If (3) lands, the privacy policy (#5) gains accuracy as a
report field, and that condition is written on that issue.

## Consequences

- The threshold question has an answer: **none**, and what would justify one is
  named below. This is the datum the project does not have — the city's crew has
  never said whether the coordinate was usable, and #177's record of 110759
  shows the answer was a hand-off for assessment, not a search.
- The block the crew reads currently overstates its own precision, and that is
  now written down in the place the next session will find it rather than being
  rediscovered from a field-test finding.
- Nothing in the code changes here. The field-test record's #31 finding (the row
  has no accuracy column, so nothing downstream can tell a good fix from a poor
  one) stays true until the follow-up issue lands.

## Options that lost

**Gate at a threshold — 100 m, or 250 m.** The option the issue is named for.
Loses on the evidence: the single real report was a 100 m fix, the city acted on
it, and refusing it would have meant the project's one real submission never
happening. A threshold chosen from one sample would be a number wearing the
clothes of a measurement.

**Coarsen the distance instead of stating the accuracy** — say no distance at all
when the fix is poor, rather than saying the fix is poor. Cheaper in reading
effort and wrong in the same way the current line is wrong: a crew told nothing
about the distance searches as though the address were the place. A crew told
"±100 m" searches the block.

**Read the bearing and describe the object as a cone.** Would put the reporter's
facing into the city's text, which is a fact about the photographer rather than
about the bin, and it still needs a distance to be useful.

**Snap the coordinate to the nearest address when the fix is poor.** Forbidden by
`AGENTS.md` — never snap a report to the nearest house — and it would destroy the
spatial resolution that #36's hot-zone question exists to preserve.

**Do nothing, including (3).** That is the state the code is in, and it leaves a
crew reading a precise-sounding sentence built on a loose fix.

## What would change this

One observation, and it is not available yet: **a crew member saying the
coordinate was not usable.** That would justify a threshold and make choosing one
a measurement rather than a guess. The city's answer to 110759 does not say it —
it says the report was closed and handed to a gardener to assess whether anything
should be planted — and nothing in the project currently asks. Until then, no
gate, and the accuracy is stated rather than enforced.
