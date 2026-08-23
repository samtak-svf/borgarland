import { describe, expect, it } from 'vitest'
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'

/**
 * #77: a tester read `{"error":"outside-reykjavik",...}` on his phone and asked
 * what it meant. The apps now say a sentence instead, from
 * data/relay-outcomes.json, and this is what stops that file drifting behind
 * the relay it describes.
 *
 * The rule the issue asked for: a code with no sentence must fail a test rather
 * than fall through to raw JSON in front of somebody. So every code this Worker
 * can put in an `error` field is held against the file, in BOTH directions — an
 * unnamed code fails, and so does a sentence for a code that no longer exists.
 *
 * **The first version of this file read one source file and was therefore not a
 * guard at all.** It scanned `src/app.ts`, while `invalid-coordinate` and
 * `invalid-description` are thrown from `src/domain.ts` on the way through
 * `createReport` and reach a person's phone exactly like the rest. Both were
 * missing from the file and the build was green. So this one reads the whole of
 * `src/`, and it refuses a code it cannot READ as well as one it cannot find:
 * a code assembled at runtime is a code no scan can check, and the scan says so
 * instead of passing.
 */
const SOURCE_DIR = join(__dirname, '../src')
const FILE = JSON.parse(readFileSync(join(__dirname, '../../data/relay-outcomes.json'), 'utf8'))

/** Every .ts file under worker/src, at any depth. */
function sourceFiles(dir: string = SOURCE_DIR): string[] {
  return readdirSync(dir).flatMap((entry) => {
    const path = join(dir, entry)
    if (statSync(path).isDirectory()) return sourceFiles(path)
    return path.endsWith('.ts') ? [path] : []
  })
}

const SOURCES = sourceFiles().map((path) => ({ path, text: readFileSync(path, 'utf8') }))

/** The two shapes a code can be answered in, as a literal. */
const THROWN = /new HttpError\(\s*\d+\s*,\s*'([a-z0-9-]+)'/g
const RETURNED = /error:\s*'([a-z0-9-]+)'/g

/**
 * The same two shapes, matched loosely, so a construction this scan cannot READ
 * is caught rather than skipped. `error: error.code` is the one deliberate
 * non-literal: it is the catch-all that re-answers an HttpError already counted
 * at its throw site.
 */
const THROWN_LOOSE = /new HttpError\(/g
const RETURNED_LOOSE = /\berror:\s*([^,}\n]+)/g

/** Every code the Worker can answer with, wherever it lives. */
function codesInSource(): Set<string> {
  const codes = new Set<string>()
  for (const { text } of SOURCES) {
    for (const match of text.matchAll(THROWN)) codes.add(match[1])
    for (const match of text.matchAll(RETURNED)) codes.add(match[1])
  }
  return codes
}

function named(): Set<string> {
  return new Set([
    ...Object.keys(FILE.outcomes),
    ...Object.keys(FILE.notShownToAnyone).filter((key) => key !== '$comment'),
  ])
}

describe('data/relay-outcomes.json', () => {
  it('reads more than one source file, which the first version of this test did not', () => {
    const paths = SOURCES.map((s) => s.path)
    expect(paths.length).toBeGreaterThan(5)
    expect(paths.some((p) => p.endsWith('app.ts'))).toBe(true)
    expect(paths.some((p) => p.endsWith('domain.ts'))).toBe(true)
  })

  it('finds the codes at all, so a rewrite of the Worker cannot make this test vacuous', () => {
    const codes = codesInSource()
    // The two the issue names explicitly, one of which only exists once the
    // relay is armed and is therefore the easiest of all to forget.
    expect(codes).toContain('outside-reykjavik')
    expect(codes).toContain('live-send-already-used')
    // And one from a file other than app.ts, which is the hole this test had.
    expect(codes).toContain('invalid-coordinate')
    expect(codes.size).toBeGreaterThan(12)
  })

  it('has a sentence for every code the relay can return, or says why not', () => {
    const missing = [...codesInSource()].filter((code) => !named().has(code))
    expect(missing, 'these codes would reach a person as an unknown answer').toEqual([])
  })

  it('has no sentence for a code the relay cannot return any more', () => {
    const codes = codesInSource()
    const stale = [...named()].filter((code) => !codes.has(code))
    expect(stale, 'these are answers to something the relay no longer says').toEqual([])
  })

  /**
   * A scan over source can only see a literal. A code built from a variable or a
   * template would pass every check above by being invisible, which is the same
   * hole in a different disguise, so it fails here instead.
   */
  it('refuses an error code this scan cannot read', () => {
    const unreadable: string[] = []
    for (const { path, text } of SOURCES) {
      const literalThrows = [...text.matchAll(THROWN)].length
      const allThrows = [...text.matchAll(THROWN_LOOSE)].length
      if (allThrows > literalThrows) {
        unreadable.push(`${path}: ${allThrows - literalThrows} HttpError(s) whose code is not a plain literal`)
      }
      for (const match of text.matchAll(RETURNED_LOOSE)) {
        const value = match[1].trim()
        // `error.code` re-answers an HttpError that was counted at its throw
        // site; a quoted literal is counted directly.
        if (value === 'error.code' || /^'[a-z0-9-]+'$/.test(value)) continue
        unreadable.push(`${path}: error field answered with ${value}, which this scan cannot check`)
      }
    }
    expect(unreadable, 'a code this test cannot read is a code with no guard').toEqual([])
  })

  it('says something in every entry, in Icelandic and without a þankastrik', () => {
    for (const [code, entry] of Object.entries<{ says: string; advice: string | null }>(FILE.outcomes)) {
      expect(entry.says.trim().length, `${code} says nothing`).toBeGreaterThan(0)
      expect(entry.says, `${code} ends without a full stop`).toMatch(/[.!?]$/)
      // The house style: no spaced en or em dash in Icelandic prose.
      expect(entry.says + ' ' + (entry.advice ?? ''), `${code} carries a þankastrik`).not.toMatch(/ [–—] /)
    }
  })

  it('carries the four outcomes that are not error codes', () => {
    for (const key of ['sent', 'dryRun', 'noAnswer', 'unknown']) {
      expect(FILE[key]?.says, `${key} has no sentence`).toBeTruthy()
    }
  })
})
