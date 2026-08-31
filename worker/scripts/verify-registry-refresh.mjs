// Verifies a registry refresh landed, per the scheduled-workflow-verklag
// rule: assert the ARTEFACT (the live registry state), not the exit code of
// the apply. A `wrangler d1 execute` that exits 0 while the seed failed to
// apply is a silent failure — the whole point of #49 is that a stale registry
// degrades the jurisdiction check quietly instead of failing it, and a cron
// that reports success on that same quietness is the state we are already in.
//
// Reads GET /api/health on the deployed relay, which reports the live row
// count, the seed's claimed count and the snapshot's age (worker/src/
// registry-loader.ts readRegistryHealth). Both facts are asserted:
//
//   rows == seededRows    the seed applied completely (a partial application
//                         shows up as a mismatch, the #48 acceptance case)
//   ageDays < 1           the snapshot is from the run that just happened,
//                         not a prior one that merely survived
//
// Exit 0 only when both hold.
const HEALTH_URL = 'https://borgarland.samtak.is/api/health'
const MAX_AGE_DAYS = 1.0

const res = await fetch(HEALTH_URL)
const body = await res.json().catch(() => null)
if (res.status !== 200 || !body || typeof body.registry !== 'object') {
  console.error(`registry refresh verification: /api/health did not answer a loaded registry (HTTP ${res.status})`)
  process.exit(1)
}

const { rows, seededRows, ageDays } = body.registry
const problems = []
if (rows !== seededRows) {
  problems.push(`rows (${rows}) != seededRows (${seededRows}) — the seed did not apply completely`)
}
if (typeof ageDays !== 'number' || ageDays >= MAX_AGE_DAYS) {
  problems.push(`snapshot is ${typeof ageDays === 'number' ? ageDays.toFixed(2) : 'unknown'} days old — the refresh did not land`)
}
if (problems.length > 0) {
  console.error('registry refresh verification FAILED: ' + problems.join('; '))
  process.exit(1)
}
console.log(`registry refresh verified: ${rows} rows, snapshot ${ageDays.toFixed(3)} days old`)
