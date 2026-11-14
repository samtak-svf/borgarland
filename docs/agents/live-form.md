# The live-form button rule

> Moved verbatim from the root `AGENTS.md`, where the rule stays as one line under the heading **Never press submit on the city's live form**. Read this on the trigger named in the root's "Rule detail" table.

This is stated as a rule about **the button** rather than about intent, because
the previous wording said "never file a real report as a test", was followed,
and a real report was filed anyway — see
[docs/incidents/2026-08-21-filed-a-real-report.md](../../docs/incidents/2026-08-21-filed-a-real-report.md).
The safeguard was a patch to `window.fetch` that never ran, and it had not been
tested before the button was pressed. A safety mechanism you have not seen fire
is not a safety mechanism.

What is allowed instead:

- **The probe.** `node scripts/send-report.mjs --category <slug> --probe` posts a
  deliberately incomplete payload that the validator must reject. It *cannot*
  succeed, which is the property that makes it safe, and
  `.github/workflows/contract.yml` runs it daily on that basis.
- **Reading the client bundle** when a payload needs observing rather than
  constructing. It is static and already downloaded; reading it cannot send.
- **One real submission, once, deliberately**, at the end of a build, with a real
  problem at a real location. That is a decision to take on purpose, never a step
  in a test. **It was taken on 2026-08-30** — reference 110759, a grass strip in
  Grafarvogur — so this line is now a record and not a permission. There is no
  second one to spend: `reserveLiveReport`'s row is claimed and the relay refuses
  another whatever the switch says. Filing one more is a code change in its own
  PR, argued for on its own merits, and #6 is where that argument belongs.
