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
// WHAT ELSE IS CHECKED, and why the list is written down. This script used to
// walk `timeline` and nothing else, while promising in this very comment to
// catch hand-copying drift in general (#90). Three sections of an entry are
// transcribed from D1 and all three were unread: `delivery`, `reports` and
// `timelineHole`. So, in full, an entry is held to:
//
//   timeline      every event against the contract's allowlist, its required
//                 fields, its enum values, its bounds, and a non-decreasing atMs
//   delivery      the batches must account for exactly the events in the
//                 timeline, in order, with bounds that are events
//   reports       an id in the format D1 stores, a category the facts file
//                 names, and a photo count that is not negative
//   timelineHole  its own arithmetic, and a gap that is really in the timeline
//   findings      an issue number
//
// What is NOT checked, and cannot be from here: whether any of it is TRUE.
// D1 is the only thing that knows, and this script has no network. It checks
// that a record is internally consistent and could have been observed.
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
/** The same shape the relay gives a report (worker/src/app.ts, randomHex(16)). */
const REPORT_ID_PATTERN = /^[0-9a-f]{32}$/

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

  checkDelivery(id, test)
  checkReports(id, test)
  checkTimelineHole(id, test)
}

/**
 * The batches must account for the timeline exactly: same number of events,
 * in order, and each batch's bounds must be the atMs of its own first and last
 * event. A batch boundary is how #74 was found, so a wrong one is not cosmetic.
 */
function checkDelivery(id, test) {
  if (test.delivery === undefined) return
  if (!Array.isArray(test.delivery)) {
    fail(id, 'delivery must be an array')
    return
  }
  const timeline = Array.isArray(test.timeline) ? test.timeline : []
  let consumed = 0
  let previousReceived = ''
  for (const [index, batch] of test.delivery.entries()) {
    if (!Number.isInteger(batch?.events) || batch.events <= 0) {
      fail(id, `delivery[${index}] carries ${JSON.stringify(batch?.events)} events`)
      continue
    }
    if (typeof batch.receivedAt !== 'string' || Number.isNaN(Date.parse(batch.receivedAt))) {
      fail(id, `delivery[${index}].receivedAt is not a timestamp: ${JSON.stringify(batch.receivedAt)}`)
    } else if (batch.receivedAt < previousReceived) {
      // A batch cannot arrive before the one before it. Equal is fine: two
      // batches can share a millisecond.
      fail(id, `delivery[${index}] arrived at ${batch.receivedAt}, before ${previousReceived}`)
    } else {
      previousReceived = batch.receivedAt
    }

    const slice = timeline.slice(consumed, consumed + batch.events)
    consumed += batch.events
    if (slice.length !== batch.events) {
      fail(id, `delivery[${index}] claims ${batch.events} events, and the timeline has ${slice.length} left`)
      continue
    }
    if (batch.firstAtMs !== slice[0]?.atMs) {
      fail(id, `delivery[${index}].firstAtMs is ${batch.firstAtMs}, and its first event is at ${slice[0]?.atMs}`)
    }
    if (batch.lastAtMs !== slice[slice.length - 1]?.atMs) {
      fail(id, `delivery[${index}].lastAtMs is ${batch.lastAtMs}, and its last event is at ${slice[slice.length - 1]?.atMs}`)
    }
  }
  if (test.delivery.length > 0 && consumed !== timeline.length) {
    fail(id, `delivery accounts for ${consumed} events and the timeline has ${timeline.length}`)
  }
}

/**
 * A report id gets the same rule the session id gets, and for the same reason
 * given there: a truncated or invented id is not the value D1 stores, so the
 * record stops linking to the row it was transcribed from.
 */
function checkReports(id, test) {
  const rows = test.reports ?? (test.report ? [test.report] : [])
  if (!Array.isArray(rows)) {
    fail(id, 'reports must be an array')
    return
  }
  for (const row of rows) {
    if (typeof row?.id !== 'string' || !REPORT_ID_PATTERN.test(row.id)) {
      fail(id, `a report id must be the 32 lowercase hex characters D1 stores; got ${JSON.stringify(row?.id)}`)
    }
    if (row?.categorySlug !== undefined && !slugs.has(row.categorySlug)) {
      fail(id, `report ${row?.id} carries category "${row.categorySlug}", which the facts file does not name`)
    }
    if (row?.photoCount !== undefined && (!Number.isInteger(row.photoCount) || row.photoCount < 0)) {
      fail(id, `report ${row?.id} carries photoCount ${JSON.stringify(row.photoCount)}`)
    }
    if (row?.dryRun !== undefined && typeof row.dryRun !== 'boolean') {
      fail(id, `report ${row?.id} carries dryRun ${JSON.stringify(row.dryRun)}, which says nothing about whether the city could be reached`)
    }
  }
}

/**
 * A hole is the one part of a record that asserts something is ABSENT, so its
 * own arithmetic is the only thing anyone can check it by.
 */
function checkTimelineHole(id, test) {
  const hole = test.timelineHole
  if (hole === undefined) return
  const bounds = hole.betweenAtMs
  if (!Array.isArray(bounds) || bounds.length !== 2 || !bounds.every(Number.isInteger)) {
    fail(id, `timelineHole.betweenAtMs must be two integers; got ${JSON.stringify(bounds)}`)
    return
  }
  const [from, to] = bounds
  if (to <= from) {
    fail(id, `timelineHole runs from ${from} to ${to}, which is not a gap`)
    return
  }
  if (hole.seconds !== undefined) {
    const expected = Math.round((to - from) / 1000)
    if (Math.abs(hole.seconds - expected) > 1) {
      fail(id, `timelineHole.seconds is ${hole.seconds}, and ${to} minus ${from} is ${expected}`)
    }
  }
  // The gap has to be a gap: both ends must be events, and nothing may sit
  // between them. A hole nobody can find in the timeline is a claim, not a
  // transcription.
  const timeline = Array.isArray(test.timeline) ? test.timeline : []
  const atMs = timeline.map((event) => event?.atMs)
  if (!atMs.includes(from) || !atMs.includes(to)) {
    fail(id, `timelineHole runs between ${from} and ${to}, and one of those is not an event in the timeline`)
    return
  }
  const inside = atMs.filter((value) => value > from && value < to)
  if (inside.length > 0) {
    fail(id, `timelineHole claims nothing between ${from} and ${to}, and the timeline has ${inside.length} event(s) there`)
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
