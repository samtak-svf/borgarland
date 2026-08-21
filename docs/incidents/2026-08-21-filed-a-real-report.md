# 2026-08-21 — a test filed a real report with the city

Report **110474** reached Reykjavík's service desk during payload research. It
described nothing real. This is the write-up, because the rule it broke is one
this repo states in three places and it still happened.

## What was sent

| | |
|---|---|
| Number | 110474 |
| Category | `ruslafotur` |
| Description | "Ruslafata við göngustíginn er yfirfull, pokar standa upp úr og fjúka." |
| Coordinate | 64.14669993360849, -21.94293675345401 — where a map click landed, near Borgartún |
| Photo | `bin.jpg`, a 485-byte solid green square generated as a test fixture |
| Email | the maintainer's, so the confirmation and any reply arrive |

Nothing at that coordinate needs attention. The city aims to answer or forward a
report "within the next weekday", so a person would have looked at it on the
Monday.

## What was being attempted

The goal was to capture the exact payload the browser builds, to diff it against
what `scripts/send-report.mjs` constructs. The plan was to patch `window.fetch`
in the page so the submission would be recorded and a synthetic response
returned, then fill the real form and press submit.

## Why it failed

The interceptor never ran. React Router's submission did not go through
`window.fetch` as patched — it either held its own reference captured at module
load, or used a native form submission. `window.__captured` was empty
afterwards, which is the proof: zero calls were intercepted, and the request
went out normally.

## The actual mistake

Not the patch. The patch was a guess about someone else's framework internals,
and guesses are allowed to be wrong.

**The mistake was pressing submit on an unverified safeguard.** The interceptor
was never tested against a harmless POST first, so there was no evidence it
worked, and the only test that would have produced evidence was the one that
could not be undone. A safety mechanism you have not seen fire is not a safety
mechanism.

A second failure sits behind it: the browser was doing this at all. The endpoint
had already been fully mapped by other means. Driving the live form to its
submit button was reaching for the one method whose failure mode is
irreversible, when several reversible methods had already answered the question.

## What changed

- **Never press submit on the city's live form.** Not with an interceptor, not
  with the network throttled, not in any circumstance. `AGENTS.md` now says this
  as a rule about the *button*, not about intent, because the previous wording
  ("never file a real report as a test") was followed and the report was filed
  anyway.
- **The probe is the only sanctioned request** to the submission route: a
  deliberately incomplete payload the validator must reject. It cannot succeed,
  which is the property that matters.
- **If a payload must be observed rather than constructed**, read the client
  bundle. It is static, it is already downloaded, and reading it cannot send
  anything.

## What it taught us anyway

Recorded because it is true, not to balance the ledger. Both of these were open
questions in `payload-map.md` and neither should have been closed this way.

- A successful submission navigates to
  `/abendingar/senda-abendingu/{slug}/done/{number}` and **the city does return a
  reference number**. The confirmation email repeats it in Icelandic, English and
  Polish.
- The confirmation carries `X-Mailer: Drupal` and a `Message-Id` from
  `rs-plesk-02-dev.rvk.borg`. The reporting system is a Drupal application behind
  the React Router front end, which fits the Drupal node ids on the categories.
- The number looks like a sequential counter. Once the app has real users, each
  number their reports come back with is a free sample of the city's total
  report volume — a figure published nowhere. That measurement needs no test
  submissions, and must never be pursued with any.

## Remediation

A withdrawal request to `upplysingar@reykjavik.is` naming 110474, sent by the
maintainer. The confirmation comes from `no-reply@`, so replying to it goes
nowhere.
