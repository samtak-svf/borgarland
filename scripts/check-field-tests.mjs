#!/usr/bin/env node
// Validates data/field-tests.json against the contracts it transcribes from.
//
// A field-test record is written by hand, after the fact, from D1 and Workers
// Logs. Hand-copied data drifts: an event name gets a plausible spelling it
// never had, a field the contract does not allow appears because it seemed
// useful, an issue number is transposed. None of that is visible by reading,
// and all of it makes the record worse than no record — a transcript nobody
// can trust is consulted once and then quietly ignored.
//
// So a timeline is held to what the Worker itself would have accepted. The
// criterion is not "does this look plausible" but "could this batch have
// crossed the wire": same allowlist, same required fields, same bounds, same
// session format as worker/src/events.ts. An event the relay would have
// refused cannot have been observed, whatever the record says.
//
// Run: node scripts/check-field-tests.mjs

import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')

// A malformed file must produce a sentence, not a stack trace. CI shows the
// last lines of a failed step, and a Node traceback there says nothing about
// which fact is wrong — which is the whole complaint this file exists to
// prevent, turned on itself.
function read(path) {
  let text
  try {
    text = readFileSync(join(root, path), 'utf8')
  } catch (error) {
    console.error(`cannot read ${path}: ${error.message}`)
    process.exit(1)
  }
  try {
    return JSON.parse(text)
  } catch (error) {
    console.error(`${path} is not valid JSON: ${error.message}`)
    process.exit(1)
  }
}

const contract = read('data/relay-events.json')
const facts = read('data/reykjavik-form.json')
const record = read('data/field-tests.json')

if (!Array.isArray(record.tests)) {
  console.error('data/field-tests.json has no "tests" array')
  process.exit(1)
}
if (!Array.isArray(facts.categories)) {
  console.error('data/reykjavik-form.json has no "categories" array')
  process.exit(1)
}

/** The Worker's own bound: an offset beyond a day is a broken clock, not a
 * session (worker/src/events.ts). */
const MAX_AT_MS = 86_400_000
const SESSION_PATTERN = /^[0-9a-f]{32}$/

const slugs = new Set(facts.categories.map((c) => c.slug))
const problems = []
const fail = (id, message) => problems.push(`${id}: ${message}`)

/** The contract spells a field as a type name or as a list of allowed values. */
function checkValue(id, event, key, spec, value) {
  if (Array.isArray(spec)) {
    if (!spec.includes(value)) {
      fail(id, `${event}.${key} = ${JSON.stringify(value)}, not one of ${spec.join(', ')}`)
    }
    return
  }
  switch (spec) {
    case 'integer':
      if (!Number.isInteger(value)) {
        fail(id, `${event}.${key} = ${JSON.stringify(value)}, expected an integer`)
      }
      return
    case 'boolean':
      if (typeof value !== 'boolean') {
        fail(id, `${event}.${key} = ${JSON.stringify(value)}, expected a boolean`)
      }
      return
    case 'categorySlug':
      if (!slugs.has(value)) {
        fail(id, `${event}.${key} = ${JSON.stringify(value)}, not a category in data/reykjavik-form.json`)
      }
      return
    default:
      // The Worker refuses an unknown spec as a contract bug rather than
      // waving it through, and so must this: a new type appearing in
      // relay-events.json without a check here would be silently unvalidated.
      fail(id, `the contract spells ${event}.${key} as "${spec}", which this script does not know how to check`)
  }
}

for (const test of record.tests) {
  const id = typeof test.id === 'string' ? test.id : '(entry with no id)'

  // The record's own shape. Every one of these is something a future reader
  // needs in order to know what the test does and does not prove.
  for (const key of ['id', 'date', 'platform', 'what', 'build', 'relay', 'timeline']) {
    if (test[key] === undefined || test[key] === null) fail(id, `missing "${key}"`)
  }
  if (test.relay && test.relay.dryRun === undefined) {
    fail(id, 'relay.dryRun is missing, so the entry does not say whether the city could have been reached')
  }
  if (typeof test.session !== 'string' || !SESSION_PATTERN.test(test.session)) {
    // Not cosmetic: a truncated id is not the value D1 stores, so the record
    // stops linking to the rows it was transcribed from.
    fail(id, `session must be the full 32 lowercase hex characters, as the relay stores it; got ${JSON.stringify(test.session)}`)
  }
  if (!Array.isArray(test.notFoundHere) || test.notFoundHere.length === 0) {
    fail(id, 'notFoundHere is empty; a test that proves everything has not been thought about')
  }

  if (test.timeline !== undefined && !Array.isArray(test.timeline)) {
    fail(id, 'timeline must be an array')
    continue
  }

  let previousAtMs = -1
  for (const event of test.timeline ?? []) {
    const spec = contract.events[event?.name]
    if (!spec) {
      fail(id, `"${event?.name}" is not an event in data/relay-events.json, so it cannot have crossed the wire`)
      continue
    }

    // The envelope the relay accepts is exactly name, atMs and fields. Anything
    // else is a key the Worker would have refused, and the likeliest reason for
    // one to appear here is a human adding a note where notes do not belong.
    for (const key of Object.keys(event)) {
      if (!['name', 'atMs', 'fields'].includes(key)) {
        fail(id, `${event.name} carries "${key}" beside name/atMs/fields, which the relay would refuse`)
      }
    }

    if (!Number.isInteger(event.atMs) || event.atMs < 0 || event.atMs > MAX_AT_MS) {
      fail(id, `${event.name} has atMs ${JSON.stringify(event.atMs)}, outside 0..${MAX_AT_MS}`)
    } else if (event.atMs < previousAtMs) {
      // Equal is fine and common: two events inside the same millisecond.
      fail(id, `${event.name} at ${event.atMs} ms goes backwards from ${previousAtMs} ms`)
    } else {
      previousAtMs = event.atMs
    }

    if (event.fields !== undefined && (event.fields === null || typeof event.fields !== 'object' || Array.isArray(event.fields))) {
      fail(id, `${event.name} has a "fields" that is not an object`)
      continue
    }
    const fields = event.fields ?? {}

    // Present-but-disallowed, and missing-but-required. The relay checks both;
    // checking only the first accepts a batch describing an event the relay
    // would have rejected for the other reason.
    for (const [key, value] of Object.entries(fields)) {
      if (!(key in spec.fields)) {
        // A string here is the shape a description or a place name would take,
        // and the contract names no free-text field anywhere. Say so, because
        // it is a privacy statement rather than a schema one.
        const note = typeof value === 'string' ? ', and the contract has no free-text field' : ''
        fail(id, `${event.name} carries "${key}", which the contract does not allow${note}`)
        continue
      }
      checkValue(id, event.name, key, spec.fields[key], value)
    }
    for (const key of Object.keys(spec.fields)) {
      if (!(key in fields)) {
        fail(id, `${event.name} is missing "${key}", which the contract requires`)
      }
    }
  }

  for (const finding of test.findings ?? []) {
    if (!Number.isInteger(finding?.issue)) {
      fail(id, `a finding has no issue number: ${finding?.what ?? '(no description)'}`)
    }
  }
}

if (problems.length > 0) {
  console.error('data/field-tests.json disagrees with the contracts it transcribes:\n')
  for (const p of problems) console.error(`  - ${p}`)
  process.exit(1)
}

const count = record.tests.length
const events = record.tests.reduce((n, t) => n + (t.timeline?.length ?? 0), 0)
console.log(`data/field-tests.json ok: ${count} field test${count === 1 ? '' : 's'}, ${events} events, all within the contract`)
