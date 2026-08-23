# Decisions

Numbered, dated records of choices this project has made and why, in the MADR
shape. A record is written **after** the discovery that justified it, never
instead of one.

Three kinds of thing are recorded separately and should not be confused:

| Where | What it holds |
|---|---|
| [`../data/`](../data/) | **Facts**, machine-readable, each carrying how and when it was established: the city's form, the request and the event stream our own apps send to our own relay, our words for a category, the platform parity manifest, and the field-test records. Scripts and CI read them. |
| [`../docs/research/`](../docs/research/) and [`../docs/incidents/`](../docs/incidents/) | **Reasoning** and write-ups. Prose, for humans. |
| `decisions/` (here) | **Choices**, with the options that lost. |

Which fact belongs in which file is spelled out once, in
[AGENTS.md](../AGENTS.md#where-things-are-written-down), and deliberately not
repeated here. This file used to carry its own copy naming two of the six, and
by the time anyone noticed it was four files out of date while claiming to be
the map. A second copy of that table is the drift the split exists to prevent,
so this one points at it instead of competing with it.

A superseded decision stays, marked superseded, with a pointer to what replaced
it. Deleting it would hide that the question was once answered differently, which
is the main thing a decision log is for.

| # | Decision | Status |
|---|---|---|
| [0001](0001-record-facts-reasoning-and-decisions-separately.md) | Record facts, reasoning and decisions in three separate places | Accepted |
| [0002](0002-relay-not-direct-post.md) | The apps post to our relay, never to the city directly | Accepted |
| [0003](0003-scope-excludes-two-categories.md) | The walking test excludes two of the city's categories | **Superseded by 0004** |
| [0004](0004-walking-test-governs-interaction.md) | The walking test governs the interaction, not the taxonomy | Accepted |
| [0005](0005-addresses-from-the-registry.md) | Addresses come from Staðfangaskrá, not from the city | Accepted |
| [0006](0006-never-press-submit.md) | Never press submit on the city's live form | Accepted |
| [0007](0007-approach-the-city-after-the-poc.md) | Approach the city after the proof of concept, not before | Accepted |
| [0008](0008-photo-analysis-suggests-never-decides.md) | Photo analysis suggests, it never decides | Accepted |
| [0009](0009-the-registry-stays-in-the-relay.md) | The registry stays in the relay, not behind greenfield's service | Accepted |
