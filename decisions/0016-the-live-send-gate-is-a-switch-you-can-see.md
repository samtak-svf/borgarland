# 0016 — The live-send gate is a switch you can see, and it has two halves

- **Date:** 2026-08-30
- **Status:** Accepted

## Context

The relay has been in dry run since it existed. Everything shipped so far —
the coordinate guard, the jurisdiction check, the reporter's address
([decision 0015](0015-the-address-is-required-by-us-and-lives-on-the-phone.md))
— was verified with the city never seeing anything. That posture ends exactly
once, deliberately, and the moment it does is the moment somebody has to be
certain which way the gate is set, from the outside, without reading source.

Until now the whole gate was `isLiveSendEnabled(env)`: true when the
`CITY_SEND_KEY` secret was set **and** its value matched
`/^[A-Za-z0-9_-]{32,}$/`. That default is right and is not what this decision
changes — absent configuration means dry run, a weak value is refused rather
than honoured, and no request can opt itself in.

Three things were wrong with it as a *control*.

**It was invisible.** A secret binding shows its presence nowhere anyone looks.
`/api/health` reported `dryRun`, which is the consequence rather than the
control: you could observe what the gate had done, never read what it was set
to.

**It had three states and could report two.** Off, armed, and *configured but
refused* — a secret somebody put as `true`, or a copy of some other variable,
or a token one character short. That third state was silent. It read as
`dryRun: true`, identical to nobody having configured anything, which made the
one configuration most likely to be a mistake the one nothing could see.

**It was not a switch.** On was `wrangler secret put`; off was
`wrangler secret delete`. Those are not the same gesture in two directions, and
neither is reversible the way a toggle is.

## Decision

**Two bindings, both required, and the resolved state is a name rather than a
boolean.**

| Binding | Kind | Arms when | Answers |
|---|---|---|---|
| `LIVE_SEND` | plain var in `wrangler.jsonc`, committed as `"off"` | trimmed, lower-cased, exactly `on` | are reports MEANT to reach the city |
| `CITY_SEND_KEY` | secret binding | matches `/^[A-Za-z0-9_-]{32,}$/` | MAY they |

`resolveLiveSend(env)` returns `{ state, switch, key }`, and `state` is one of
four: `off`, `armed`, `key-refused`, `key-missing`. Only `armed` sends.
`/api/health` reports the whole readout beside `dryRun`, on the 503 as well as
the 200, because a degraded relay is exactly when somebody is looking.

### Why the switch is a committed var, having argued it must not be

`src/config.ts` used to carry the opposite argument, and it was a good one: a
plain `DRY_RUN=false` lives in committed config, one typo away from a live
deploy and one copy-paste away from travelling into another environment.

That argument assumed the variable would be the *whole* gate. It is half of
one. A stray `"on"` reaching another environment finds no `CITY_SEND_KEY`
there and arms nothing — and, the part that matters more, it **says so**, as
`key-missing`, rather than looking like a relay somebody deliberately turned
off.

With the capability secret still guarding the send, what the var buys is the
property a secret cannot have: `grep LIVE_SEND worker/wrangler.jsonc` answers
"is this live?" without account access, and flipping it is one edit in either
direction. It also makes going live a commit, a review and a deploy on a public
repository — which is what [decision 0006](0006-never-press-submit.md) wants
that act to cost, not an obstacle to route around.

### Why the switch honours no near-misses

`true`, `1`, `yes`, `enabled` do not arm it. They read as `unrecognised`, which
is reported rather than silently treated as off — the same principle as
`key-refused`. A typo that reads as "off" is how somebody concludes the switch
is broken when it is their spelling.

### What is deliberately untouched

Decision 0006's one-real-submission gate — the D1 row `reserveLiveReport`
claims before the city is posted to (#98). This decision is about the control
in front of that gate. Lifting the "one" is still a code change in its own PR.

The `dryRun` boolean in the **report response body** is also untouched. Both
apps read it to choose which Icelandic sentence to show
(`data/relay-outcomes.json`), and it is a fact about a report rather than a
readout of configuration.

## Consequences

- The gate is strictly stricter than it was. An environment holding a valid
  `CITY_SEND_KEY` and nothing else used to POST to the city; it is now dry run.
  Production held no key at all when this shipped (`/api/health` answered
  `dryRun: true` on 2026-08-30), so nothing in flight changed behaviour — but a
  key put at any point in the past would have been armed the whole time, which
  is itself part of why the switch exists.
- Going live now takes two people-visible acts instead of one invisible one.
  That is the intent.
- `worker/tests/config.test.ts` pins all four states and, specifically, that a
  strong secret with the switch off does not send. `worker/tests/relay.test.ts`
  asserts the same thing behaviourally, where the fixture throws on an
  unexpected city call.

## Options that lost

**Keep `CITY_SEND_KEY` as the sole authority and only add a readable surface.**
The smallest change, and it fixes visibility and the third state. It does not
fix the asymmetric gesture: on and off remain `secret put` and `secret delete`.
Rejected for solving two of three problems while the third is the one that
makes the control feel like a control.

**Move the authority to a D1 row or KV value that a small admin path flips,
with the secret as a second factor.** A genuine two-way toggle, and the only
option where flipping it needs no deploy. Rejected: it puts an authenticated
mutation endpoint on a public relay whose entire security argument today is
that it has none — a new auth story, a new attack surface, and a switch that
can be flipped without a review, for a gate that is meant to be pulled once.

**A `wrangler.jsonc` var that CI asserts is `false` on every deploy.** Rejected
in that form: an assertion that the switch is off can never be satisfied by the
deploy that turns it on, so going live would mean changing the guard in the
same breath — which trains everyone to treat the guard as noise. CI asserting
the var is *present and one of the two known values* would be worth having, and
is left for a follow-up rather than smuggled in here.
