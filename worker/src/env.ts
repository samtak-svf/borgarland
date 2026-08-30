// The Worker's environment bindings.
//
// DB is a D1 database (created with `--jurisdiction eu` — see AGENTS.md).
//
// LIVE_SEND and CITY_SEND_KEY are the two halves of the live-send gate, and
// BOTH are required to take the relay out of dry run (#168). LIVE_SEND is the
// switch and lives as a plain var in wrangler.jsonc, committed as "off", so
// that its position is readable without listing secrets and flipping it is one
// gesture in either direction. CITY_SEND_KEY is the capability: a strong token
// held as a SECRET binding, which no edit to committed config can supply. See
// config.ts for how each is checked and for the states /api/health reports.

export interface Env {
  DB: D1Database
  /**
   * Photographs, kept for 30 days by a lifecycle rule on the bucket itself.
   *
   * They are kept so a report can be REVIEWED before it is promoted (#181):
   * the operator deciding whether an ábending is worth filing for real cannot
   * make that call from a category and a coordinate. Nothing else reads them,
   * and the relay still stores no address.
   */
  PHOTOS: R2Bucket
  /** Plain var. `"on"` arms the switch; absent, `"off"` or anything else does not. */
  LIVE_SEND?: string
  /** Secret binding. Absent or weak → the relay stays in dry run. */
  CITY_SEND_KEY?: string
}
