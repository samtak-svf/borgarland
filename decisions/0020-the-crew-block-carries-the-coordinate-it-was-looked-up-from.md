# 0020 — The crew block carries the coordinate it was looked up from

- **Date:** 2026-09-15
- **Status:** Accepted

## Context

The relay appends a block to the reporter's own text before it sends the report
to the city. It has appended the nearest registered address since the address
work landed (`#202`): `Næsta skráða heimilisfang: Gullengi 37, 112 Reykjavík`.

That line is a **reverse lookup**, and nothing in it said so. `AGENTS.md` states
the rule twice, *"The registry is a convenience, never a constraint"* and
*"Never snap a report to the nearest house"* — but the crew member reading the
ábending has not read `AGENTS.md`. To them the line reads as *the address of the
report*, which is precisely the reading the coordinate-first design exists to
avoid. On the 2026-08-31 walk the line named `Gullengi 37` for a coordinate that
is not it, and the city's answer to report 110759 quoted back `Gullengi 39` from
a different walk: neighbouring houses, neither of them where the thing was.

Two facts shaped the decision:

- **The coordinate is already submitted**, in the city's own `lat`/`lng` fields,
  so whether the crew can see it depends entirely on their tooling. We have
  never seen their screen.
- **The description is the one surface we know they read.** The city quotes it
  back in its closing email (`data/reykjavik-form.json`
  `fields.email.answerEmail`), which is both evidence that it is read and the
  reason both ends see whatever we append.

The distance was already known and already stored (`jurisdiction_km`, #186) and
had never been said out loud.

## Decision

**The appended block says three things, and the first two are the correction.**
The reporter's text stays first and untruncated; the block goes after it:

```
<the reporter's own description>

Næsta skráða heimilisfang í Staðfangaskrá: Gullengi 37, 112 Reykjavík, 40 m frá hnitinu.
Hnit: 64.1487542, -21.780545
```

- **The register is named.** `í Staðfangaskrá` makes the lookup a lookup: a
  source, not a statement by the reporter.
- **The distance is stated**, which is the other half of the same point. An
  address 40 m away cannot be read as the position once the sentence says how
  far away it is.
- **The coordinate is printed under it**, `String(latitude)` and
  `String(longitude)` — the same expression the adapter uses for the city's own
  `lat`/`lng` fields, so the text and the fields cannot disagree: one number,
  formatted once, in two places.

**The coordinate's format is a deliberate choice, not a default:** decimal
degrees, period separator, latitude first, comma and space between. A coordinate
is a number a device reads, and the Icelandic decimal comma is not what any map
takes. The number of decimals is whatever the app sent; nothing is re-rounded.

**The distance rounds to what the fix can support.** Metres below a kilometre,
kilometres above it, Icelandic decimal comma. Below ten metres it says
`minna en 10 m` rather than rounding to zero, because the photograph it was
measured from declared an accuracy of 3.54 m
(`docs/research/photos-exif-and-formats.md`) and a finer figure would claim an
accuracy nobody has. Ten-metre steps below a kilometre for the same reason.

**The block is atomic.** If it does not fit inside the city's 2500-character
limit it is dropped whole, exactly as the single line was before: the reporter's
text is never cut to make room for ours. A half-block would put the coordinate
in the text without the line that says what the numbers beside it are.

## Consequences

- A crew reading the ábending can tell where the thing is from where the
  address is. The design decision survives contact with someone who has never
  read our documents.
- The reporter sees the same block in the city's closing email, so they too are
  told the address was a lookup rather than a claim they made.
- The block is ~100 characters, well inside the limit; `composeDescription`
  still drops it rather than truncate.
- Nothing about what is submitted as the position changes. The coordinate
  remains the only positional field, and no report is snapped to an address.
- `nearestAddressKm` in #202's text is `jurisdiction_km` in the code; the issue
  named a field that does not exist under that name. The row keeps its 2-decimal
  rounding and the text rounds independently for display.

## Options that lost

**A `geo:` URI.** Machine-actionable on a phone, and unusable in the one place
this text is known to be read: a mail client on a desktop, and a work queue we
have never seen. Also invisible as a coordinate to a human skimming it.

**A maps link.** Same objection, plus two more. The city stores this text and
quotes it back, so a link becomes a stored, forwarded reference to a
third-party mapping service with our report's position in it; and whether a link
in their queue is clickable at all is unknown. A pair of numbers can always be
typed into whatever map they already have.

**Keep the address line and only label it.** `Næsta skráða heimilisfang (flett
upp)` says what the line is without saying where the report is. The crew still
has to open their own tooling with a coordinate that was never given to them.

**Put the strings in a data file.** `data/category-labels.json` and
`data/relay-outcomes.json` hold our words for a reader, which is the family this
text belongs to. Both of those exist because **apps** read them, on both
platforms, and no app composes this block: the relay is its only reader and its
only writer. It stays beside the function that builds it, where it can be read
in one piece, and `worker/tests/relay.test.ts` holds the composed output to the
same standard those files are held to.
