#!/usr/bin/env node
//
// Fails when a summary screen does not list a part the app sends.
//
//   node scripts/check-summary-fields.mjs
//
// The screen is headed "Það sem yrði sent" ("what would be sent") and says it
// shows exactly what crosses the line. It was untrue twice: reportId was sent
// and not listed (#88), then accuracy (#254). Both times the contract grew a
// part and nobody remembered the two screens.
//
// data/relay-request.json is the one place the parts are named, so this reads
// it and requires every part to have a row in SummaryScreen.kt and
// SummaryScreen.swift. `photo` has no FieldRow: it is drawn as a heading and a
// thumbnail, so its heading is looked for instead. The rows must also appear in
// the contract's order, so the two screens stay the same screen.

import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (rel) => readFileSync(join(ROOT, rel), 'utf8')

/** Line and block comments removed, so a comment naming a part is not a row. */
const stripComments = (text) => text.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '')

const parts = Object.keys(JSON.parse(read('data/relay-request.json')).fields)

const SCREENS = [
  { name: 'Android', file: 'android/app/src/main/kotlin/is/borgarland/ui/SummaryScreen.kt', row: /FieldRow\(\s*"(\w+)"/g, photo: /Text\(\s*"photo"/ },
  { name: 'iOS', file: 'ios/Sources/SummaryScreen.swift', row: /FieldRow\(\s*label:\s*"(\w+)"/g, photo: /Text\("photo"\)/ },
]

const failures = []
for (const screen of SCREENS) {
  const text = stripComments(read(screen.file))
  const listed = [...text.matchAll(screen.row)].map((m) => m[1])
  if (screen.photo.test(text)) listed.push('photo')
  // Not sorted: the contract's order is the order the rows must come in. `photo`
  // is last in the contract and drawn after the rows, so appending it holds.
  for (const part of parts) {
    if (!listed.includes(part)) failures.push(`${screen.name} (${screen.file}) does not list '${part}'`)
  }
  for (const label of listed) {
    if (!parts.includes(label)) failures.push(`${screen.name} lists '${label}', which data/relay-request.json does not name`)
  }
  if (!failures.length && JSON.stringify(listed) !== JSON.stringify(parts)) {
    failures.push(`${screen.name} lists [${listed.join(', ')}], the contract's order is [${parts.join(', ')}]`)
  }
}

// Empty evidence is not a pass: the contract must have named something.
if (parts.length === 0) failures.push('data/relay-request.json names no parts')

if (failures.length) {
  console.error(failures.map((f) => `check-summary-fields: ${f}`).join('\n'))
  process.exit(1)
}
console.log(`check-summary-fields: both summary screens list all ${parts.length} parts of data/relay-request.json`)
