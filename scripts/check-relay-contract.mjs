#!/usr/bin/env node
//
// Fails when the two sides of the relay request contract drift apart.
//
// data/relay-request.json is the one place the multipart field names live;
// the Worker (worker/src/app.ts) reads it and rejects any part it does not
// name, the Android build copies it into assets and the app constructs its
// request from it, and this script pins the file itself: the field set, the
// requiredness, the endpoint, the absence of the city's vocabulary (the old
// app sent type, summary, the display name, lat/lng and files), and the parts
// that restate city facts (the description limit, the photo MIME list) must
// agree with data/reykjavik-form.json.
//
//   node scripts/check-relay-contract.mjs              # file-level checks
//   node scripts/check-relay-contract.mjs --require-asset  # + the Android asset
//                                                       # copy is byte-identical
//
// CI runs it on every PR that touches either side, and the Worker's test
// suite (worker/tests/contract.test.ts) and the Android test suite
// (RelayRequestTest) enforce the same contract behaviorally.

import { readFile } from 'node:fs/promises'

const ROOT = new URL('..', import.meta.url)
const read = (p) => readFile(new URL(p, ROOT), 'utf8')

const contract = JSON.parse(await read('data/relay-request.json'))
const facts = JSON.parse(await read('data/reykjavik-form.json'))
const contractRaw = await read('data/relay-request.json')

const failures = []
const check = (ok, message) => {
  if (!ok) failures.push(message)
}

// The one documented shape. The order is the order the app writes the parts in.
const EXPECTED_FIELDS = ['reportId', 'session', 'category', 'latitude', 'longitude', 'description', 'email', 'photo']
const fieldNames = Object.keys(contract.fields ?? {})
check(
  JSON.stringify(fieldNames) === JSON.stringify(EXPECTED_FIELDS),
  `fields must be exactly [${EXPECTED_FIELDS.join(', ')}], got [${fieldNames.join(', ')}]`,
)

// The old app sent the city's vocabulary; none of those names may reappear.
for (const name of ['type', 'summary', 'lat', 'lng', 'files']) {
  check(!fieldNames.includes(name), `fields must not include the city's '${name}'`)
}
// And no city display name or summary string may appear anywhere in the file:
// the contract speaks our vocabulary, and the adapter derives the rest.
for (const category of facts.categories) {
  check(
    !contractRaw.includes(category.category),
    `the contract must not restate the city's display name '${category.category}'`,
  )
  check(
    !contractRaw.includes(category.summary),
    `the contract must not restate the city's summary '${category.summary}'`,
  )
}

// Requiredness, which is the APP's obligation and not the relay's tolerance.
//
// The two used to be the same thing, and the comment here said "as the relay
// enforces it" while that happened to hold for all seven fields. It never
// described the mechanism: the Worker reads this file for the unknown-field
// allowlist alone (worker/src/app.ts) and hardcodes each field's own parse.
// What actually reads `required` is the valueFor(name) loop in both apps,
// which refuses to build a body without a required part.
//
// `email` is where the two diverge on purpose (#163). The app must send one;
// the relay still accepts a report without one, because builds 6 and 7 are on
// testers' phones and send none. worker/tests/contract.test.ts pins that
// tolerance, so the divergence cannot be closed by accident on either side.
const REQUIRED = { category: true, latitude: true, longitude: true, description: true, email: true, photo: false }
for (const [name, expected] of Object.entries(REQUIRED)) {
  check(
    contract.fields[name]?.required === expected,
    `fields.${name}.required must be ${expected}`,
  )
}

check(
  contract.endpoint?.path === '/api/reports' &&
    contract.endpoint?.method === 'POST' &&
    contract.endpoint?.contentType === 'multipart/form-data',
  'endpoint must be POST multipart/form-data at /api/reports',
)

// The parts that restate city facts must agree with the facts file.
check(
  contract.fields.description?.maxLength === facts.fields.description.maxLength,
  `description.maxLength must equal the city facts (${facts.fields.description.maxLength}), got ${contract.fields.description?.maxLength}`,
)
check(
  JSON.stringify(contract.fields.photo?.accept) === JSON.stringify(facts.fields.files.accept),
  `photo.accept must equal the city facts (${facts.fields.files.accept.join(', ')}), got ${contract.fields.photo?.accept?.join(', ') ?? 'missing'}`,
)

// Both sides must actually read the file rather than restate it.
const appSource = await read('worker/src/app.ts')
check(
  appSource.includes('data/relay-request.json'),
  'worker/src/app.ts must import data/relay-request.json (a second copy is a copy that drifts)',
)
const gradleSource = await read('android/app/build.gradle.kts')
check(
  gradleSource.includes('relay-request.json'),
  'android/app/build.gradle.kts must copy data/relay-request.json into assets',
)

// The asset copy is current. Only meaningful after a Gradle build created it;
// CI runs the Android test suite first, then passes --require-asset.
if (process.argv.includes('--require-asset')) {
  const asset = await read('android/app/src/main/assets/relay-request.json')
  check(
    asset === contractRaw,
    'android/app/src/main/assets/relay-request.json is not byte-identical to data/relay-request.json',
  )
}

if (failures.length > 0) {
  console.error('relay request contract check failed:')
  for (const failure of failures) console.error(`  - ${failure}`)
  process.exit(1)
}

console.log(
  '✓ relay request contract holds: eight fields in order, no city vocabulary, facts in agreement, both sides reading the file',
)
