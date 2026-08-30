#!/usr/bin/env node
//
// Decision 0006's one real submission, taken on purpose, on a report that is
// already stored (decision 0017).
//
//   node scripts/promote-report.mjs --id <32 hex> --email <address> [--review]
//   node scripts/promote-report.mjs --id <32 hex> --email <address> --send
//
// It will NOT send without --send, for the same reason `send-report.mjs` will
// not: the flag is the deliberate act, and a script that files a real ábending
// as a side effect of being run is the safeguard that failed on 2026-08-21
// (docs/incidents/2026-08-21-filed-a-real-report.md).
//
// --review downloads the report's photographs and prints the row, which is the
// judgement this whole path exists to make possible. Look before you promote:
// a category and a coordinate cannot tell you whether an ábending is worth
// filing with the city.
//
// The credential is CITY_SEND_KEY, read from the environment. It is the
// operator's, no app holds it, and it is the only thing standing between this
// script and the city — together with the LIVE_SEND switch, which the relay
// checks for itself and reports at /api/health.

import { writeFile } from 'node:fs/promises'

const RELAY = process.env.BORGARLAND_RELAY ?? 'https://borgarland.samtak.is'

function arg(name) {
  const i = process.argv.indexOf(`--${name}`)
  return i === -1 ? null : process.argv[i + 1]
}

function die(message) {
  console.error(`✗ ${message}`)
  process.exit(1)
}

const id = arg('id')
const email = arg('email')
const review = process.argv.includes('--review')
const send = process.argv.includes('--send')
const key = process.env.CITY_SEND_KEY

if (!id || !/^[0-9a-f]{32}$/.test(id)) die('--id must be 32 lowercase hex characters (the reportId the app shows on its summary screen)')
if (!key) die('CITY_SEND_KEY is not set. It is the operator credential; the relay refuses without it.')

const auth = { Authorization: `Bearer ${key}` }

// Always show what is about to happen, whether or not it is about to happen.
const health = await (await fetch(`${RELAY}/api/health`)).json()
console.log(`relay      ${RELAY}`)
console.log(`liveSend   ${JSON.stringify(health.liveSend)}`)
console.log(`one        ${JSON.stringify(health.oneSubmission)}`)

const rowResponse = await fetch(`${RELAY}/api/reports/${id}`)
if (rowResponse.status === 404) die(`no report ${id} is stored on this relay`)
const { report } = await rowResponse.json()
console.log('\nthe report you would file:')
for (const field of ['id', 'categorySlug', 'latitude', 'longitude', 'photoCount', 'photoBytes', 'createdAt', 'dryRun']) {
  console.log(`  ${field.padEnd(13)} ${report[field]}`)
}
console.log(`  description   ${JSON.stringify(report.description)}`)
console.log(`  email         ${email ?? '(none supplied — required to send)'}`)

if (review) {
  for (let i = 0; i < report.photoCount; i++) {
    const photo = await fetch(`${RELAY}/api/reports/${id}/photo/${i}`, { headers: auth })
    if (!photo.ok) {
      console.error(`  photo ${i}: ${photo.status} — expired, or never stored`)
      continue
    }
    const path = `/tmp/borgarland-${id}-${i}.jpg`
    await writeFile(path, Buffer.from(await photo.arrayBuffer()))
    console.log(`  photo ${i}: ${path}`)
  }
}

if (!send) {
  console.log('\nNothing was sent. Pass --send to file this with Reykjavíkurborg for real.')
  console.log('Decision 0006 permits one, ever; after it, this refuses.')
  process.exit(0)
}

if (!email) die('--email is required to send: the city answers by email and by nothing else, and the relay stores none')

const form = new FormData()
form.append('email', email)
const response = await fetch(`${RELAY}/api/reports/${id}/promote`, { method: 'POST', headers: auth, body: form })
const body = await response.json()

if (response.status === 200 && body.alreadyLive) {
  console.log(`\n· already filed — city reference ${body.report.cityReference ?? '(none read)'}`)
  process.exit(0)
}
if (response.status === 200) {
  console.log(`\n✓ filed. City reference ${body.report.cityReference}, sent at ${body.report.sentAt}.`)
  console.log('  The confirmation goes to the address above, not to this machine.')
  process.exit(0)
}

console.error(`\n✗ ${response.status} ${body.error}${body.reason ? `: ${body.reason}` : ''}`)
process.exit(1)
