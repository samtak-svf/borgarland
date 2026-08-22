// The dry-run gate. This is the one place the relay decides whether the final
// POST to the city may happen, and its default is the safe path: doing nothing
// (deploying with no extra configuration) leaves the relay in dry run, where it
// does everything except the POST, records the row and returns what it would
// have sent.
//
// Taking the relay live is a deliberate act, not a default and not a plain
// variable:
//
//   - The gate is a SECRET binding (CITY_SEND_KEY). A plain variable like
//     `DRY_RUN=false` lives in the committed wrangler.jsonc, where it is one
//     edit away from a typo'd live deploy and one copy-paste away from
//     travelling into another environment. A secret cannot live in committed
//     config; it has to be generated and put deliberately with
//     `wrangler secret put CITY_SEND_KEY` against a specific account and
//     environment.
//
//   - The value must be a strong token (≥32 characters of [A-Za-z0-9_-]). A
//     casual value — "true", "false", "1", a copy of some other variable, a
//     typo — fails the shape check and the relay stays in dry run. The only way
//     to pass is to deliberately generate a strong random token.
//
// There is deliberately no per-request way to opt out: a buggy or malicious app
// cannot force a live send. Only the operator's secret can, and the operator
// cannot get there by accident.

import type { Env } from './env'

const LIVE_SEND_KEY_PATTERN = /^[A-Za-z0-9_-]{32,}$/

export function isLiveSendEnabled(env: Pick<Env, 'CITY_SEND_KEY'>): boolean {
  const key = env.CITY_SEND_KEY
  return typeof key === 'string' && LIVE_SEND_KEY_PATTERN.test(key)
}

export function isDryRun(env: Pick<Env, 'CITY_SEND_KEY'>): boolean {
  return !isLiveSendEnabled(env)
}
