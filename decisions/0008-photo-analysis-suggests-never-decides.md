# 0008 — Photo analysis suggests, it never decides

- **Date:** 2026-08-21
- **Status:** Accepted

## Context

The camera is the entry point ([0004](0004-walking-test-governs-interaction.md)),
and all twelve of the city's categories are in the app. That leaves a design
problem with no good answer inside a plain form: a person standing outside in the
rain has to pick one of twelve categories and then write an Icelandic sentence
into an empty box, before anything happens at all.

A model that reads the photo could remove both. Every field the city accepts can
be derived or suggested: `lat`/`lng` from EXIF, `type` and `summary` from the
category, `files` from the photo itself, `email` from a remembered setting, and
the two hard ones — `category` and `description` — from the photograph. The
screen stops being a form and becomes a single confirmation.

That is also the danger. This project has already filed one real report by
accident ([the incident](../docs/incidents/2026-08-21-filed-a-real-report.md)),
with an invented description and a meaningless coordinate. Prefilling every field
and offering one button is that accident with a production line behind it.

### What was measured

A real field photograph — an overflowing bin (ruslafata) on a paved footpath,
with a dog in frame — was run through Gemini on 2026-08-21. One model did both
the seeing and the Icelandic.

What worked:

- `waste-bins` picked correctly on both runs, `confidence: high`, with
  `household-waste` and `general-suggestion` correctly offered as defensible
  alternatives.
- `"Græn ruslafata við hellulagðan göngustíg er yfirfull af plastpokum."` —
  accurate, specific, and free of speculation about cause or duration.
- The dog was in the frame and was correctly left out of the report.

What failed, and both failures shaped this decision:

- Asked what the photo could not show, it asked **"Hvar nákvæmlega er þessi
  ruslafata staðsett?"** — where the bin is. That is the one question the app
  must never ask, because the coordinate arrived with the photograph. The model
  does not know what the app already knows, so it spent its only question on
  solved ground.
- `privacy_flags: []`, with a dog, a building and a fence in the frame. It is not
  a reliable privacy screen.
- 12.3 seconds for a short answer, 28.5 for a richer one. Not a spinner a person
  waits on outside.

The Workers AI catalogue was checked the same day: no vision model there
documents Icelandic, and Llama 3.2's language set excludes it.

## Considered options

### A. No analysis. A twelve-item picker and an empty box
- ➕ Nothing to build, nothing to disclose, no model to be wrong.
- ➖ The form the camera-first rule exists to avoid, reached one screen later.

### B. On-device only (ML Kit / Gemini Nano, Vision / Foundation Models)
- ➕ The photo never leaves the phone. Instant, free, works with no signal, and
  the suggestion can appear while the shot is still being framed.
- ➖ Generic label sets do not map onto the city's taxonomy, the same reason
  `resnet-50` is unusable here.
- ➖ Only recent devices support the capable models, so the relay path has to
  exist anyway for everyone else. This is additional work, not alternative work.
- ➖ Frozen at release. A classifier that turns out to be poor in the dark waits
  for an App Store review, which is the exact failure [0002](0002-relay-not-direct-post.md)
  was written to avoid.

### C. In the relay, third-party model
- ➕ One model does vision and Icelandic together, demonstrated above.
- ➕ Swappable in a deploy.
- ➖ The photograph leaves our infrastructure. Photographs of the public realm
  carry faces, plates and people's windows; one category is literally about
  photographing vehicle plates.

### D. In the relay, our own infrastructure (Workers AI, same account)
- ➕ The photo stays where the relay already is.
- ➖ No vision model there speaks Icelandic.

### E. Split the job: vision on our infrastructure, Icelandic text elsewhere
- ➕ Only the vision step sees the photograph. The text step sees words.
- ➖ Two calls, two failure modes, more latency on a path that is already slow.

## Decision

**Analysis produces a suggestion, and a person decides.** That is the part being
settled here, and it holds whichever model is chosen:

1. **It suggests, it never sends.** No path files a report without a person
   having read what is about to be filed in their name.
2. **It never blocks.** The suggestion arrives when it arrives. Every path
   through the app completes without it, because it will sometimes be slow and
   sometimes absent.
3. **What is interpreted stays visible.** The coordinate, the photo and the
   address are observed and may be filled silently. `type` and `summary` are
   derived and need no attention. `category` and `description` are interpretations
   and must be on screen and easy to correct. A field the user never sees is a
   field the user cannot correct.
4. **The prompt states what the app already knows**, so the model does not spend
   its attention on the location, which arrived with the photograph.
5. **It is not a privacy screen.** We do not claim to detect faces, plates or
   bystanders on the strength of a model that missed a dog.
6. **Our vocabulary, not the city's.** The model returns our own category names;
   `worker/src/adapters/reykjavik.ts` maps them to the city's slugs. The rule in
   AGENTS.md is not suspended because the caller is a model.

**Server first, device later.** The relay path is built first because it has to
exist for the devices that cannot do this locally, and because it can be
corrected in a deploy. The UI contract is *a suggestion may appear*; who produced
it is swappable, so moving it on-device later for speed and privacy needs no
redesign.

## Open, deliberately

**Where the model runs is not settled.** Option C is proven to work and sends the
photograph to a third party. Option D keeps it home and cannot write Icelandic.
Option E splits the difference at the cost of latency the measurements say we can
ill afford. Deciding this needs the privacy position from #5, so it is recorded
here as open rather than guessed at.

## Consequences

- **#5 gains a second disclosure.** "Your photo is sent to the city" and "your
  photo is also read by a model" are different sentences and a reader deserves
  both. Whether the photo is retained after the suggestion is produced, and
  whether it leaves our infrastructure, are now policy questions, not just
  engineering ones.
- The screen must be designed around a suggestion that may be late or missing,
  from the first sketch. Retrofitting that onto a screen that assumes it is
  present is a redesign.
- The description field stops asking "write something" and starts asking for what
  the photograph cannot show. That is a much easier question to answer outside,
  and it is exactly the part automation cannot supply.
- Whatever model is chosen needs a real accuracy measurement across the twelve
  categories before the suggestion is trusted in the interface, not one bin on
  one afternoon.
