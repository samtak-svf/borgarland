import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

/**
 * #77: a tester read `{"error":"outside-reykjavik",...}` on his phone and asked
 * what it meant. The apps now say a sentence instead, from
 * data/relay-outcomes.json, and this is what stops that file drifting behind
 * the relay it describes.
 *
 * The rule the issue asked for: a code with no sentence must fail a test rather
 * than fall through to raw JSON in front of somebody. So every code this
 * Worker can put in an `error` field is held against the file, in BOTH
 * directions — an unnamed code fails, and so does a sentence for a code that no
 * longer exists.
 *
 * Read from the source rather than from a list, because a list is a second
 * place to forget.
 */
const SOURCE = readFileSync(join(__dirname, '../src/app.ts'), 'utf8')
const FILE = JSON.parse(readFileSync(join(__dirname, '../../data/relay-outcomes.json'), 'utf8'))

/** Every code the Worker can answer with, however it is thrown or returned. */
function codesInSource(): Set<string> {
  const codes = new Set<string>()
  for (const match of SOURCE.matchAll(/new HttpError\(\s*\d+\s*,\s*'([a-z-]+)'/g)) {
    codes.add(match[1])
  }
  for (const match of SOURCE.matchAll(/json\(\s*\{\s*error:\s*'([a-z-]+)'/g)) {
    codes.add(match[1])
  }
  return codes
}

describe('data/relay-outcomes.json', () => {
  it('finds the codes at all, so a rewrite of app.ts cannot make this test vacuous', () => {
    const codes = codesInSource()
    // The two the issue names explicitly, one of which only exists once the
    // relay is armed and is therefore the easiest of all to forget.
    expect(codes).toContain('outside-reykjavik')
    expect(codes).toContain('live-send-already-used')
    expect(codes.size).toBeGreaterThan(8)
  })

  it('has a sentence for every code the relay can return, or says why not', () => {
    const named = new Set([
      ...Object.keys(FILE.outcomes),
      ...Object.keys(FILE.notShownToAnyone).filter((key) => key !== '$comment'),
    ])
    const missing = [...codesInSource()].filter((code) => !named.has(code))
    expect(missing, 'these codes would reach a person as raw JSON').toEqual([])
  })

  it('has no sentence for a code the relay cannot return any more', () => {
    const codes = codesInSource()
    const stale = [...named()].filter((code) => !codes.has(code))
    expect(stale, 'these are answers to something the relay no longer says').toEqual([])
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

function named(): Set<string> {
  return new Set([
    ...Object.keys(FILE.outcomes),
    ...Object.keys(FILE.notShownToAnyone).filter((key) => key !== '$comment'),
  ])
}
