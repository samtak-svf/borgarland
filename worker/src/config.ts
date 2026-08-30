// The live-send gate. This is the one place the relay decides whether the final
// POST to the city may happen, and its default is the safe path: deploying with
// no extra configuration leaves the relay in dry run, where it does everything
// except the POST, records the row and returns what it would have sent.
//
// It is TWO things, and they answer different questions (#168).
//
//   - LIVE_SEND is the SWITCH: whether reports are meant to go to the city. It
//     is a plain var in wrangler.jsonc, committed as "off", because a switch's
//     whole job is to be readable — `grep LIVE_SEND wrangler.jsonc` answers
//     "is this live?" without listing anyone's secrets, and flipping it is the
//     same gesture in both directions rather than `secret put` one way and
//     `secret delete` the other. It also means going live is a commit and a
//     review, which is what decision 0006 wants it to cost.
//
//   - CITY_SEND_KEY is the CAPABILITY: a strong token (≥32 characters of
//     [A-Za-z0-9_-]) held as a secret binding, which the switch alone cannot
//     conjure. A casual value — "true", "1", a copy of some other variable, a
//     typo — fails the shape check and the relay stays in dry run. The only way
//     to pass is to deliberately generate a strong random token and put it with
//     `wrangler secret put CITY_SEND_KEY` against a specific account.
//
// Both are required. That is why a committed var is safe here in a way an
// earlier version of this file argued it would not be: a stray "on" reaching
// another environment finds no key there and arms nothing, and — the part that
// matters — it says so, as `key-missing`, instead of looking like off.
//
// Which is the whole point of resolving to a NAMED STATE rather than a boolean.
// The old gate had three states and could only report two: a CITY_SEND_KEY that
// was set but refused by the pattern was indistinguishable from no key at all,
// so the one configuration most likely to be a mistake was the one nothing
// could see. Every state below is reported by /api/health.
//
// There is deliberately no per-request way to opt out: a buggy or malicious app
// cannot force a live send. Only the operator's own configuration can, and the
// operator cannot get there by accident.

import type { Env } from './env'

const LIVE_SEND_KEY_PATTERN = /^[A-Za-z0-9_-]{32,}$/

type GateEnv = Pick<Env, 'CITY_SEND_KEY' | 'LIVE_SEND'>

/** Where the switch is set. Absent reads as `off`; that is the enforced default. */
export type SwitchPosition = 'on' | 'off' | 'unrecognised'

/** What the capability secret is in. */
export type KeyCondition = 'valid' | 'refused' | 'absent'

/**
 * The resolved gate. Only `armed` sends.
 *
 * `key-refused` and `key-missing` exist so that "the switch is on but nothing
 * will happen" is a state somebody can read, rather than a silence they have to
 * infer by checking a regex against a secret they cannot see.
 */
export type LiveSendState = 'off' | 'armed' | 'key-refused' | 'key-missing'

export interface LiveSendReadout {
  state: LiveSendState
  switch: SwitchPosition
  key: KeyCondition
}

function readSwitch(value: unknown): SwitchPosition {
  if (typeof value !== 'string') return 'off'
  const normalised = value.trim().toLowerCase()
  if (normalised === '') return 'off'
  if (normalised === 'on') return 'on'
  if (normalised === 'off') return 'off'
  // Not "true", not "1", not "yes". A switch that honoured near-misses would be
  // guessing at intent on the one decision this project refuses to guess at —
  // and an unrecognised value is reported as itself rather than quietly as off,
  // because a typo that reads as "off" is how somebody concludes the switch is
  // broken when it is their spelling.
  return 'unrecognised'
}

function readKey(value: unknown): KeyCondition {
  if (typeof value !== 'string' || value === '') return 'absent'
  return LIVE_SEND_KEY_PATTERN.test(value) ? 'valid' : 'refused'
}

/**
 * The gate, resolved. Safe to serialise: it names conditions, never values.
 */
export function resolveLiveSend(env: GateEnv): LiveSendReadout {
  const position = readSwitch(env.LIVE_SEND)
  const key = readKey(env.CITY_SEND_KEY)

  // The switch is asked first, so that an off relay is `off` whatever the key
  // is in — but `key` still reports the key's own condition, so a refused
  // secret is legible before the switch is ever flipped rather than at the
  // moment somebody is depending on it.
  const state: LiveSendState =
    position !== 'on'
      ? 'off'
      : key === 'valid'
        ? 'armed'
        : key === 'refused'
          ? 'key-refused'
          : 'key-missing'

  return { state, switch: position, key }
}

export function isLiveSendEnabled(env: GateEnv): boolean {
  return resolveLiveSend(env).state === 'armed'
}

export function isDryRun(env: GateEnv): boolean {
  return !isLiveSendEnabled(env)
}
