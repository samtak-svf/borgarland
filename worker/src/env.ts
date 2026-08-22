// The Worker's environment bindings.
//
// DB is a D1 database (created with `--jurisdiction eu` — see AGENTS.md).
//
// CITY_SEND_KEY is the one deliberate act that takes the relay out of dry run.
// It is a SECRET binding, never a plain variable: variables live in
// wrangler.jsonc, which is committed and easy to flip; a secret has to be
// generated and put with `wrangler secret put` against a real Cloudflare
// account. See config.ts for how its shape is enforced.

export interface Env {
  DB: D1Database
  /** Secret binding. Absent or weak → the relay stays in dry run. */
  CITY_SEND_KEY?: string
}
