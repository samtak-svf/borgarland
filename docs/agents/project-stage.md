# Project stage and the purpose limit

> Moved verbatim from the root `AGENTS.md`, where the rule stays as one line under the heading **What stage this is, and what the data is for**. Read this on the trigger named in the root's "Rule detail" table.

**The app is a proof of concept.** The feasibility question is answered — the
city's endpoint was reverse-engineered, the relay carries a report end to end,
and exactly one real ábending was filed on purpose (110759, decision 0006). No
second one can be: `reserveLiveReport`'s row is claimed and the relay refuses
another whatever the switch says. Nothing here is a service yet.

**So the data exists to prove the app works, and nothing else.** The telemetry,
the session join, `data/field-tests.json` — all of it is there so a walk can be
reconstructed and a defect diagnosed with nobody in the room. That is why
`data/relay-events.json` names no free-text field and no coordinate: it is
diagnostic data about software, deliberately not data about people or places.

**Do not justify anything here by what the data could later become.** The
reports would add up to a map showing where the same thing keeps going wrong,
and [#36](https://github.com/samtak-svf/borgarland/issues/36) is that idea —
titled, deliberately, *"that is a different purpose than the one we collected
them for."* It is a purpose that would need its own argument, its own consent
story and its own decision record. Reaching for it as a reason to do something
today is the exact collapse the purpose limit exists to prevent.

Recorded because a session did it, 2026-08-31: asked what the project's north
star was, it answered that the app is becoming "a record of what the city does
with reports" and justified the measurement discipline by that — two messages
after quoting #36 approvingly. Guðröður corrected it. The discipline needs no
such justification, and the real one is smaller and harder: **at proof-of-concept
stage the only thing you have is whether your claims about your own app are
true.** A box reported as ticked that is not, or a test green for the wrong
reason, does not spoil a future dataset. It means you do not know whether the
thing works, which is the whole question at this stage.
