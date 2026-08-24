// Reconciles private/screenshots against the index in private/testers.json.
//
// This gate can never run in CI, and that is the point rather than a gap:
// `private/` holds real names, addresses and chat identifiers, this repository
// is public, and the whole convention is that none of it is ever committed. So
// the check runs where the data actually is -- one developer's machine -- and
// exits 0 with a word when the directory is absent.
//
// It exists because of a specific miss on 2026-08-24: three screenshots from
// the first walk of build 6 were pulled out of a chat thread and written to
// disk, the field-test entry was written and merged, and NOBODY indexed the
// images. Five indexed against eight on disk, caught by a person asking rather
// than by anything automatic. An unindexed screenshot is worse than a missing
// one: it looks like evidence and says nothing, and the reader who needs it
// most is the one who cannot open it.
//
// Run: node scripts/check-private-index.mjs
import { readFileSync, readdirSync, existsSync } from 'node:fs'

const DIR = 'private/screenshots'
const ROSTER = 'private/testers.json'

if (!existsSync(ROSTER)) {
  console.log('private/ is not on this machine — nothing to reconcile, which is correct in CI.')
  process.exit(0)
}

const roster = JSON.parse(readFileSync(ROSTER, 'utf8'))
const files = roster.screenshots?.files ?? []
const indexed = new Map(files.map((f) => [f.file, f]))
const onDisk = existsSync(DIR) ? readdirSync(DIR).filter((n) => !n.startsWith('.')) : []

const problems = []

for (const name of onDisk) {
  const entry = indexed.get(name)
  if (!entry) {
    problems.push(`${name}: on disk, absent from the index. Describe it or delete it.`)
    continue
  }
  // A filename is not a description. The index promises the record is readable
  // without opening the image, so an entry that says nothing fails too.
  for (const key of ['tester', 'platform', 'takenAt', 'shows']) {
    if (!entry[key]) problems.push(`${name}: indexed but has no \`${key}\`.`)
  }
  if (entry.shows && entry.shows.length < 80) {
    problems.push(`${name}: \`shows\` is ${entry.shows.length} characters. Say what is ON the screen, not what it is about.`)
  }
}

for (const name of indexed.keys()) {
  if (!onDisk.includes(name)) {
    problems.push(`${name}: indexed, not on disk. The index describes evidence nobody can look at.`)
  }
}

if (problems.length > 0) {
  console.error(`private/screenshots and its index in ${ROSTER} disagree:\n`)
  for (const p of problems) console.error(`  - ${p}`)
  console.error(`\n  ${onDisk.length} on disk, ${indexed.size} indexed.`)
  process.exit(1)
}

console.log(`private/screenshots ok: ${onDisk.length} screenshots, every one indexed and described.`)
