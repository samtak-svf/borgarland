# Decisions

Numbered, dated records of choices this project has made and why, in the MADR
shape. A record is written **after** the discovery that justified it, never
instead of one.

Three kinds of thing are recorded separately and should not be confused:

| Where | What it holds |
|---|---|
| [`../data/`](../data/) | **Facts**, machine-readable, each carrying how and when it was established, plus the files holding our own words rather than the city's. Scripts and CI read them. Deliberately not listed here: this row named six files by hand and was one short within a fortnight, which is the drift its own warning below is about. (One, not four: the four belongs to the sentence below it, about an earlier version that named two of six. Borrowing a number from the paragraph you are correcting is its own small instance of the same failure.) |
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
| [0010](0010-the-report-carries-its-own-id.md) | The report carries its own id, and the relay stores it as the row | Accepted |
| [0011](0011-the-queue-refuses-rather-than-evicts.md) | The offline queue refuses rather than evicts | Accepted |
| [0012](0012-android-ships-on-a-personal-play-account.md) | Android ships, on a personal Play account and not the party's | Accepted |
| [0013](0013-the-follow-up-asks-the-phone-not-the-person.md) | The follow-up asks the phone, not the person | Accepted |
| [0014](0014-a-simulator-checks-behaviour-not-pixels.md) | A simulator checks behaviour, not pixels | Accepted |
| [0015](0015-the-address-is-required-by-us-and-lives-on-the-phone.md) | The reporter's address is required by us, and lives on the phone | Accepted |
| [0016](0016-the-live-send-gate-is-a-switch-you-can-see.md) | The live-send gate is a switch you can see, and it has two halves | Accepted |
| [0017](0017-the-live-send-is-an-operator-act-not-a-request.md) | The live send is an operator act, not something a request can cause | Accepted |
| [0018](0018-the-saved-copy-carries-no-exif-gps.md) | The saved copy carries no EXIF GPS | Accepted |
| [0019](0019-a-capability-ships-when-android-is-device-verified.md) | A capability ships when Android is device-verified and iOS is CI-green | Accepted |
