// The smallest seed the refresh may publish.
//
// The seed opens with `DELETE FROM addresses`, so applying a short one empties
// the live registry and the relay refuses every report (503
// registry-not-loaded). That happened on 2026-11-06: the HMS export streamed
// zero rows, the generator wrote a seed holding only the DELETE, the scheduled
// apply ran it and production lost all 139,765 addresses. The export recovered
// within hours; the registry did not, until the job was re-run by hand.
//
// Staðfangaskrá had ~139.8k usable rows on 2026-11-06 and grows slowly. 120k
// sits far below any real count and far above any truncated or empty
// download, so a refusal means the export broke, never that the country
// shrank. If the real count ever approaches it, raise it here.
export const MIN_SEED_ROWS = 120_000

/** Throws unless `count` rows are enough to replace the live registry. */
export function assertSeedFloor(count, floor = MIN_SEED_ROWS) {
  if (!Number.isInteger(count) || count < floor) {
    throw new Error(
      `refusing to publish a seed of ${count} address rows (floor ${floor}): ` +
        'it would replace the live registry with a short one; the previous registry stays',
    )
  }
}
