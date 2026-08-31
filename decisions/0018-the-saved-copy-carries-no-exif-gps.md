# 0018 — The saved copy carries no EXIF GPS

- **Date:** 2026-08-31
- **Status:** Accepted

## Context

[#179](../README.md) saves the captured photograph to the device gallery, so a
person keeps their picture after filing. It was raised and deliberately left
open whether the saved copy should carry the coordinate:

> The captured photograph carries no EXIF GPS. CameraX does not write it… So a
> saved copy lands in the gallery **with no location**, which is its own small
> surprise: a picture of a pothole that does not know where it was.
>
> The app holds the coordinate and could write it into the saved copy's EXIF.
> That would make the picture self-locating and match what every other camera
> app produces — but it also embeds a location in a file the person may share
> onward, which is a disclosure the app would be making on their behalf.
>
> Raised here deliberately rather than settled. It probably wants a decision
> record of its own, and it should not be decided by whichever implementation
> is easiest.

The claim that every other camera app produces a self-locating picture is
worth testing rather than adopting: an app's shutter press is the person's
intent to make a picture, and a location is part of what a camera app is for.
Here the shutter press is intent to **report**. The picture is evidence first
and a memory second. When the person later shares the evidence, they share what
they saw; embedding where they were when they saw it adds what they did not say.

The relay's own posture is the nearest precedent. `data/relay-events.json`
deliberately names no free-text field and no device identifier (#128): the
project has consistently treated metadata that travels with content as
something to justify, not something to add. An EXIF GPS block is metadata that
travels with a file the app does not control afterwards — it survives
re-encoding, cropping and every share path, and the person cannot see it
without tooling. The disclosure is invisible at the moment it happens.

## Decision

**The saved copy is the photograph the app took, with nothing added.** No EXIF
GPS is written. The coordinate belongs to the report, is submitted with it, and
stays out of the file the person owns and may share.

The photograph was captured without EXIF (CameraX writes none; the iOS capture
path asks for JPEG and the camera adds none), so "no GPS in the saved copy" is
also "the saved copy is byte-faithful to what the camera produced". Writing the
coordinate would mean rewriting the JPEG — an encoding step the app otherwise
never performs, on both platforms.

## Consequences

- A saved picture in the gallery does not know where it was. That is stated in
  the issue as the cost, and accepted: the surprise of a picture without a
  location is smaller than the surprise of a shared picture that carries one.
- The report path is unchanged: the coordinate still travels with the report,
  is resolved by the relay's jurisdiction check, and reaches the city.
- If a person wants a self-locating picture, the tooling they already have
  (the device's own camera app) produces one, and the gallery offers "share
  location" in the apps that support it. The app does not need to become that
  tooling.
- Implementation is simpler on both platforms, but this record exists to say
  the simplicity is a consequence, not the reason.

## Options that lost

**Write the coordinate into the saved copy's EXIF.** Self-locating and matches
other camera apps. Lost on disclosure: the app would embed a location in a file
it does not control afterwards, invisible to the person sharing it. The
app's own standard elsewhere is that metadata which travels with content is
justified or absent (#128, the events allowlist).

**Ask the person at capture time whether to embed the location.** A per-picture
prompt on the shutter is exactly the second form on the path to a report that
[0004](0004-walking-test-governs-interaction.md) exists to prevent, and the
question is hard to answer honestly in the two seconds before the shot. If the
feature is ever wanted, the setting belongs beside the save toggle — but there
is no evidence yet that anyone wants it, so no setting is built.

**Embed only when the report's jurisdiction check passed.** Uses the relay's
answer to change what the app writes, which couples the two and would make the
saved copy depend on a network verdict about a coordinate the device already
has. Rejected for the coupling, not for the outcome.
