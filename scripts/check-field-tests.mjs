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
// So the timeline is checked against data/relay-events.json, which is the
// allowlist the Worker itself enforces. If an event could not have crossed
// the wire, it cannot have been observed, and the entry is wrong.
//
// Run: node scripts/check-field-tests.mjs

import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p) => JSON.parse(readFileSync(join(root, p), 'utf8'))

const contract = read('data/relay-events.json')
const facts = read('data/reykjavik-form.json')
const { tests } = read('data/field-tests.json')

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
  if (spec === 'integer' && !Number.isInteger(value)) {
    fail(id, `${event}.${key} = ${JSON.stringify(value)}, expected an integer`)
  }
  if (spec === 'boolean' && typeof value !== 'boolean') {
    fail(id, `${event}.${key} = ${JSON.stringify(value)}, expected a boolean`)
  }
  if (spec === 'categorySlug' && !slugs.has(value)) {
    fail(id, `${event}.${key} = ${JSON.stringify(value)}, not a category in data/reykjavik-form.json`)
  }
}

for (const test of tests) {
  const id = test.id ?? '(entry with no id)'

  // The record's own shape. Every one of these is something a future reader
  // needs in order to know what the test does and does not prove.
  for (const key of ['id', 'date', 'platform', 'what', 'build', 'relay', 'timeline']) {
    if (test[key] === undefined) fail(id, `missing "${key}"`)
  }
  if (test.relay && test.relay.dryRun === undefined) {
    fail(id, 'relay.dryRun is missing, so the entry does not say whether the city could have been reached')
  }
  if (!Array.isArray(test.notFoundHere) || test.notFoundHere.length === 0) {
    fail(id, 'notFoundHere is empty; a test that proves everything has not been thought about')
  }

  let previousAtMs = -1
  for (const event of test.timeline ?? []) {
    const spec = contract.events[event.name]
    if (!spec) {
      fail(id, `"${event.name}" is not an event in data/relay-events.json, so it cannot have crossed the wire`)
      continue
    }

    if (!Number.isInteger(event.atMs) || event.atMs < 0) {
      fail(id, `${event.name} has atMs ${JSON.stringify(event.atMs)}`)
    } else if (event.atMs < previousAtMs) {
      // Equal is fine and common: two events inside the same millisecond.
      fail(id, `${event.name} at ${event.atMs} ms goes backwards from ${previousAtMs} ms`)
    } else {
      previousAtMs = event.atMs
    }

    const fields = event.fields ?? {}
    for (const [key, value] of Object.entries(fields)) {
      if (!(key in spec.fields)) {
        fail(id, `${event.name} carries "${key}", which the contract does not allow`)
        continue
      }
      checkValue(id, event.name, key, spec.fields[key], value)
    }

    // The privacy boundary, restated where a human is typing. The contract
    // names no free-text field anywhere; a string that is not one of a fixed
    // set of values means something was transcribed that could not have been
    // sent, and the likeliest something is content.
    for (const [key, value] of Object.entries(fields)) {
      const spec2 = spec.fields[key]
      if (typeof value === 'string' && !Array.isArray(spec2) && spec2 !== 'categorySlug') {
        fail(id, `${event.name}.${key} is a string, and the contract has no free-text field`)
      }
    }
  }

  for (const finding of test.findings ?? []) {
    if (!Number.isInteger(finding.issue)) {
      fail(id, `a finding has no issue number: ${finding.what ?? '(no description)'}`)
    }
  }
}

if (problems.length > 0) {
  console.error('data/field-tests.json disagrees with the contracts it transcribes:\n')
  for (const p of problems) console.error(`  - ${p}`)
  process.exit(1)
}

const count = tests.length
const events = tests.reduce((n, t) => n + (t.timeline?.length ?? 0), 0)
console.log(`data/field-tests.json ok: ${count} field test${count === 1 ? '' : 's'}, ${events} events, all within the contract`)
