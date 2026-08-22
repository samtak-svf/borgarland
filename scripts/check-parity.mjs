#!/usr/bin/env node
//
// Reports which capabilities each app has, and fails when that disagrees with
// what data/platform-parity.json says it should be.
//
//   node scripts/check-parity.mjs          # table + exit 1 on a violation
//   node scripts/check-parity.mjs --quiet  # only the violations
//
// The problem this exists for: the two apps drifted apart and nothing said so.
// iOS gained Crashlytics and a signed release pipeline while Android gained
// neither; both facts were true for hours and were found by a person reading the
// code. Individual gaps have issues; nothing detected a NEW gap.
//
// The design point is that the manifest does NOT record what exists. `intent` is
// a human decision — parity, ios-only, android-only, neither-yet — and `detect`
// is a pattern. This script finds the truth and compares. A hand-kept matrix
// rots exactly like a stale comment; the closest thing to prior art
// (dashpay/platform's SDK parity manifest, the only CI-enforced parity system
// found in open source as of 2026-08-22) hand-audits its statuses for that
// reason, and this is the version that does not have to.
//
// What it deliberately does NOT do: enforce parity. Whether Android follows iOS
// is a decision per capability (#58). It enforces that the decision is written
// down.

import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const QUIET = process.argv.includes('--quiet')

const manifest = JSON.parse(readFileSync(join(ROOT, 'data/platform-parity.json'), 'utf8'))

const SKIP_DIRS = new Set(['node_modules', '.git', 'build', '.gradle', 'dist', 'Pods'])

/** Every file under a path, or the path itself when it is a file. */
function filesUnder(rel) {
  const abs = join(ROOT, rel)
  if (!existsSync(abs)) return null // signalled to the caller: a bad path is a config error
  if (statSync(abs).isFile()) return [abs]
  const out = []
  ;(function walk(dir) {
    for (const entry of readdirSync(dir)) {
      if (SKIP_DIRS.has(entry)) continue
      const p = join(dir, entry)
      const s = statSync(p)
      if (s.isDirectory()) walk(p)
      else out.push(p)
    }
  })(abs)
  return out
}

const problems = []

/** True when the pattern occurs anywhere under the declared paths. */
function detect(capability, platform, spec) {
  const re = new RegExp(spec.pattern)
  let searched = 0
  for (const rel of spec.paths) {
    const files = filesUnder(rel)
    if (files === null) {
      // A renamed or deleted directory would otherwise read as "the capability
      // is absent", which is the same shape as a real regression and would be
      // acted on as one.
      problems.push(
        `config: ${capability.name}/${platform} names a path that does not exist: ${rel}`,
      )
      continue
    }
    searched += files.length
    for (const file of files) {
      let text
      try {
        text = readFileSync(file, 'utf8')
      } catch {
        continue // a binary or unreadable file is not where a capability lives
      }
      if (re.test(text)) return true
    }
  }
  if (searched === 0) {
    problems.push(`config: ${capability.name}/${platform} searched zero files`)
  }
  return false
}

const rows = []

for (const capability of manifest.capabilities) {
  const android = detect(capability, 'android', capability.detect.android)
  const ios = detect(capability, 'ios', capability.detect.ios)
  const { name, intent, reason } = capability

  let verdict = 'ok'
  if (intent === 'parity') {
    if (android !== ios) {
      verdict = 'DRIFT'
      const has = android ? 'Android' : 'iOS'
      const lacks = android ? 'iOS' : 'Android'
      problems.push(
        `${name}: declared parity, but ${has} has it and ${lacks} does not. ` +
          `Build it on ${lacks}, or change the intent to ${android ? 'android-only' : 'ios-only'} with a reason.`,
      )
    } else if (!android && !ios) {
      // Both absent under a parity intent is ambiguous by construction: either
      // it regressed on both platforms at once, or the detector is wrong. Both
      // are worth a human, and silence would be wrong for either.
      verdict = 'ABSENT'
      problems.push(
        `${name}: declared parity and found on NEITHER platform. ` +
          `Either it regressed on both, or the detector no longer matches. Check before trusting this file.`,
      )
    }
  } else if (intent === 'ios-only' && android) {
    verdict = 'DRIFT'
    problems.push(`${name}: declared ios-only, but Android has it now. Update the intent.`)
  } else if (intent === 'android-only' && ios) {
    verdict = 'DRIFT'
    problems.push(`${name}: declared android-only, but iOS has it now. Update the intent.`)
  } else if (intent === 'neither-yet' && (android || ios)) {
    verdict = 'DRIFT'
    const who = android && ios ? 'both platforms' : android ? 'Android' : 'iOS'
    problems.push(
      `${name}: declared neither-yet, but ${who} has it now. ` +
        `Something shipped without this file being updated, which is the drift this check exists to catch.`,
    )
  }

  if ((intent === 'ios-only' || intent === 'android-only') && !reason) {
    problems.push(`${name}: intent ${intent} requires a written reason naming an issue.`)
  }

  rows.push({ name, intent, android, ios, verdict })
}

if (!QUIET) {
  const mark = (b) => (b ? 'yes' : ' — ')
  const w = Math.max(...rows.map((r) => r.name.length))
  console.log('')
  console.log(`  ${'capability'.padEnd(w)}  ${'intent'.padEnd(12)}  android  ios      `)
  console.log(`  ${'-'.repeat(w)}  ${'-'.repeat(12)}  -------  -------  `)
  for (const r of rows) {
    const flag = r.verdict === 'ok' ? '' : `  <- ${r.verdict}`
    console.log(
      `  ${r.name.padEnd(w)}  ${r.intent.padEnd(12)}  ${mark(r.android).padEnd(7)}  ${mark(r.ios).padEnd(7)}${flag}`,
    )
  }
  console.log('')
}

if (problems.length > 0) {
  console.error('Platform parity check failed:\n')
  for (const p of problems) console.error(`  - ${p}`)
  console.error(
    '\nThis is a decision, not a chore: either build the missing side, or record in\n' +
      'data/platform-parity.json why one platform deliberately has it and the other does not.\n',
  )
  process.exit(1)
}

console.log(`Platform parity: ${rows.length} capabilities, no undeclared drift.`)
