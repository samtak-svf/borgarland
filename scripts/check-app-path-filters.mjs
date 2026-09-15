#!/usr/bin/env node
//
// Fails when an app workflow's `paths:` filter does not cover every data file
// that app bundles.
//
//   node scripts/check-app-path-filters.mjs          # table + exit 1 on a gap
//   node scripts/check-app-path-filters.mjs --quiet  # only the gaps
//
// The problem this exists for (#194): ios-ci.yml and android-ci.yml both
// triggered on `data/**`, and only four files under data/ reach an app. One
// commit that changed data/field-tests.json — 190 lines of a walk transcript —
// started ios-ci (two macOS jobs, ~13½ min), android-ci, relay-request-contract,
// contract and platform-parity. The only workflow that could say anything about
// it was field-tests, which took 16 seconds.
//
// Narrowing the filter is the easy half. This is the half that keeps it narrow:
// the moment a fifth data file is bundled, the filter is stale again, and the
// failure is silent — the workflows simply stop running on the change that the
// bundle check would have caught.
//
// Where "which files an app bundles" lives, and why this compares rather than
// asserts:
//
//   ios/project.yml               referenced in place with `- path: ../data/…`
//   android/app/build.gradle.kts  copied into assets by the copy* tasks
//   ios-ci.yml's bundle check     names the four and byte-compares them
//
// Three copies, each true in its own place. The `paths:` filter is a fourth,
// and it is the one that can be wrong without anything failing. This reads all
// four and reports the disagreement.
//
// It fails on the gap in one direction only: a bundled file the filter does not
// name. The other direction — a filter entry that is not bundled — costs a
// trigger nobody needed and is printed as a note, because a workflow may
// legitimately watch a file it does not bundle.

import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const QUIET = process.argv.includes('--quiet')

const read = (rel) => readFileSync(join(ROOT, rel), 'utf8')

/** Where each app's bundle comes from, and the workflow whose filter covers it. */
const APPS = [
  {
    name: 'iOS',
    workflow: '.github/workflows/ios-ci.yml',
    source: 'ios/project.yml',
    // `- path: ../data/reykjavik-form.json`, under buildPhase: resources.
    pattern: /^\s*-\s*path:\s*\.\.\/data\/(\S+)\s*$/gm,
  },
  {
    name: 'Android',
    workflow: '.github/workflows/android-ci.yml',
    source: 'android/app/build.gradle.kts',
    // `from(rootProject.file("../data/reykjavik-form.json"))` in the copy* tasks.
    pattern: /rootProject\.file\("\.\.\/data\/([^"]+)"\)/g,
  },
]

/**
 * The bundle check in ios-ci.yml names the four files a second time, in two
 * shell loops. It is checked too, because a fifth file that reaches the app and
 * not this step leaves the step verifying four of five while reporting success.
 */
const BUNDLE_CHECK = {
  name: 'ios-ci bundle check',
  file: '.github/workflows/ios-ci.yml',
  pattern: /for f in ([^;]+); do/g,
}

// ---------------------------------------------------------------------------
// Reading the workflows. There is no YAML parser in this repository and this is
// not worth adding one for, so the `on:` block is read line by line. It fails
// loudly rather than returning an empty list when it cannot find what it wants:
// a checker that silently examined nothing would pass, which is the one result
// it must never produce.
// ---------------------------------------------------------------------------

const indentOf = (line) => line.length - line.trimStart().length
const unquote = (value) => value.replace(/^['"]|['"]$/g, '')

function triggerPaths(rel) {
  const lines = read(rel).split('\n')
  const start = lines.findIndex((line) => /^on:\s*$/.test(line))
  if (start === -1) throw new Error(`${rel}: no top-level 'on:' block to read`)

  const stack = []
  const lists = []
  for (let i = start + 1; i < lines.length; i++) {
    const line = lines[i]
    if (line.trim() === '' || line.trimStart().startsWith('#')) continue
    if (/^\S/.test(line)) break // left the `on:` block

    const indent = indentOf(line)
    const trimmed = line.trim()
    while (stack.length > 0 && indent <= stack[stack.length - 1].indent) stack.pop()

    if (/^paths:\s*$/.test(trimmed)) {
      const paths = []
      for (let j = i + 1; j < lines.length; j++) {
        const item = lines[j]
        if (item.trim() === '' || item.trimStart().startsWith('#')) continue
        const match = item.match(/^\s*-\s*(.+?)\s*$/)
        if (indentOf(item) > indent && match) {
          paths.push(unquote(match[1]))
          continue
        }
        break
      }
      lists.push({ event: stack.map((entry) => entry.name).join('.') || 'on', paths })
      continue
    }

    stack.push({ indent, name: trimmed.replace(/:\s*$/, '') })
  }

  if (lists.length === 0) throw new Error(`${rel}: found no 'paths:' list under 'on:'`)
  return lists
}

/** `**` crosses a separator, `*` does not — the two characters GitHub documents. */
function covers(pattern, path) {
  const source = pattern
    .replace(/[.+^${}()|[\]\\]/g, '\\$&')
    .replace(/\*\*/g, '\u0000')
    .replace(/\*/g, '[^/]*')
    .replace(/\u0000/g, '.*')
  return new RegExp(`^${source}$`).test(path)
}

function bundled(app) {
  const names = [...read(app.source).matchAll(app.pattern)].map((m) => m[1])
  if (names.length === 0) {
    throw new Error(`${app.source}: found no bundled data files — the pattern is stale, not the app`)
  }
  return names.map((name) => `data/${name}`)
}

const problems = []
const notes = []
const bundledByName = new Map()

for (const app of APPS) {
  const files = bundled(app)
  bundledByName.set(app.name, files)
  const lists = triggerPaths(app.workflow)

  for (const { event, paths } of lists) {
    const missing = files.filter((file) => !paths.some((pattern) => covers(pattern, file)))
    const checked = paths.filter((pattern) => pattern.startsWith('data/'))
    if (!QUIET) {
      const state = missing.length === 0 ? `${files.length}/${files.length}` : `${files.length - missing.length}/${files.length}`
      console.log(`${app.name.padEnd(8)} ${app.workflow.padEnd(34)} ${event.padEnd(14)} ${state}`)
    }
    for (const file of missing) {
      problems.push(`${app.workflow} (${event}): ${file} is bundled by ${app.source} and does not match any entry in the filter`)
    }
    for (const pattern of checked) {
      if (!files.some((file) => covers(pattern, file))) {
        notes.push(`${app.workflow} (${event}): watches ${pattern}, which ${app.name} does not bundle (harmless, but it is a trigger nobody needed)`)
      }
    }
  }
}

// The iOS bundle check, compared against the iOS bundle source.
const iosNames = bundledByName.get('iOS').map((file) => file.replace(/^data\//, ''))
const loops = [...read(BUNDLE_CHECK.file).matchAll(BUNDLE_CHECK.pattern)]
if (loops.length === 0) {
  throw new Error(`${BUNDLE_CHECK.file}: no \`for f in …; do\` bundle check found — the step moved, and this check is now examining nothing`)
}
for (const [index, match] of loops.entries()) {
  const listed = match[1].trim().split(/\s+/)
  const absent = iosNames.filter((name) => !listed.includes(name))
  if (absent.length > 0) {
    problems.push(
      `${BUNDLE_CHECK.file}: the bundle check's loop #${index + 1} (${listed.join(' ')}) does not name ` +
        `${absent.join(', ')}, which ${APPS[0].source} bundles`,
    )
  }
}

for (const note of notes) console.log(`note: ${note}`)

if (problems.length > 0) {
  console.error('')
  for (const problem of problems) console.error(`✗ ${problem}`)
  console.error('')
  console.error('A data file an app bundles has to be in that workflow\'s `paths:` filter, or the')
  console.error('workflow stops running on the change it exists to check (#194).')
  process.exit(1)
}

if (!QUIET) console.log(`\nApp path filters: ${APPS.length} apps, no data file bundled that the filter does not cover.`)
