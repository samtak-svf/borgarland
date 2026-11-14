# Where things are written down: the full table

> Moved verbatim from the root `AGENTS.md`, where the rule stays as one line under the heading **Where things are written down**. Read this on the trigger named in the root's "Rule detail" table.

One job each. Putting a fact in the wrong one is how they drift.

No number in that sentence any more: it said "four" while the table held eight,
which is what a count in prose does the third time the list grows.

| Where | What |
|---|---|
| [`data/reykjavik-form.json`](../../data/reykjavik-form.json) | **Facts** about the city's form, with how and when each was established. `scripts/send-report.mjs` and `.github/workflows/contract.yml` read it. Change a fact here first. |
| [`data/relay-request.json`](../../data/relay-request.json) | **Facts** about the request the apps send to OUR relay, in our vocabulary only. Both sides read it: the Worker rejects any part it does not name, and both apps build the request from it. A request-contract fact belongs here, never in the city's facts file and never in prose. |
| [`data/relay-events.json`](../../data/relay-events.json) | **Facts** about the client event stream the apps send to OUR relay. Its allowlist is the privacy boundary: every field is a number, a boolean or a fixed enum, and it deliberately names no free-text field, so a description or a coordinate cannot travel this channel even by mistake. Adding a string field here is a privacy decision, not a schema change. |
| [`data/relay-outcomes.json`](../../data/relay-outcomes.json) | **Our words** for what the relay answered, one sentence per outcome, in the language of the person filing. Separate from the city's facts for the same reason as the labels file: those record what the CITY says, this is what WE say to somebody about what happened. No Icelandic sentence for a relay answer belongs in Swift or Kotlin — both apps read this, and the mapping returns nothing rather than inventing a fallback. `worker/tests/outcomes.test.ts` holds it to every error code the Worker's own source can answer with, so a code with no sentence fails the build. |
| [`data/category-labels.json`](../../data/category-labels.json) | **Our words** for a category, where the city's are wrong for someone standing in front of the thing. The only place an app may override a label from the facts file, and separate from it on purpose: that one is a faithful record of what the city says, this is where we disagree. A slug absent here renders the city's own name, which should stay the common case. |
| [`data/platform-parity.json`](../../data/platform-parity.json) | **Facts** about which capabilities each app has, and the INTENT for each: parity, one-sided with a written reason, or neither-yet. `scripts/check-parity.mjs` detects the truth from the source and fails CI when it disagrees. The file does not assert what exists; that is the point. |
| [`data/field-tests.json`](../../data/field-tests.json) | **Observations** from a build in a hand, on a real device, against the live relay. Each entry keeps what was OBSERVED apart from what was CONCLUDED: the timeline and the report row are transcribed from D1 and must not be edited to fit a later understanding, while `findings` is interpretation and may be revised. `scripts/check-field-tests.mjs` validates every timeline against the event allowlist, because an event that could not cross the wire cannot have been observed. The defects that reach this file are the ones no test and no CI run can see. |
| `private/testers.json` **(gitignored, not in this repo)** | **People.** Who has been asked to test, on which channel, what they were told and what happened, plus `howToInvite` — the invite-flow traps, each one written the day somebody hit it. It is gitignored because it holds real names, addresses and chat identifiers and this repository is public. It is listed here anyway, because a file a future session does not know about gets re-derived from chat scrollback, and that is how a person gets asked twice or forgotten. Its `screenshots` index is reconciled against `private/screenshots` by `scripts/check-private-index.mjs`, which is the one gate in this table that CANNOT run in CI and must not: the data is real names and real addresses. See **When new test data arrives**. |
| `private/city-correspondence/` **(gitignored, not in this repo)** | **Mail from the city**, kept as received — the confirmations for reports 110474 and 110759, and the city's answer to 110759 (a different kind of mail: the closure notice that is the first real outcome signal #57 is about). It is addressed mail carrying a real address, so it is gitignored for the same reason `private/testers.json` is — and listed here for the same reason too: the facts it establishes are in `data/reykjavik-form.json` under `fields.email.confirmationEmail`, `fields.email.answerEmail` and `measurement.reportVolume`, and a future session that does not know the originals exist will re-derive them from memory or not at all. |
| [`docs/research/`](../../docs/research/), [`docs/incidents/`](../../docs/incidents/) | **Reasoning**, and write-ups of what went wrong. |
| [`decisions/`](../../decisions/) | **Choices**, MADR shape, with the options that lost. A superseded record stays, marked superseded. |

The reasoning behind this split is [decision 0001](../../decisions/0001-record-facts-reasoning-and-decisions-separately.md).

**One of those files is not in the repository, on purpose.** `private/testers.json`
holds the tester roster and the contact log, and `private/` is gitignored — the
same convention `samtak-vefur` uses for anything carrying a name or an address.
Everything in it is personal data about volunteers, so it must never be
committed, quoted in an issue, or pasted into a PR body. What belongs in public
is the *lesson*, not the person: when an invite goes wrong, the trap goes in
`howToInvite` there and, if it is general, into the `play-console` skill.

It earns its place because the invite flow has more traps than the app does.
Play notifies a new internal tester of nothing at all; the opt-in URL works only
with the track id and not the app id; and tapping that URL inside a chat app's
own browser cannot complete the opt-in, which every tester invited over
Messenger or Discord will do first. All three were found by watching one person
try, on 2026-08-24.
