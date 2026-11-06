import { describe, expect, it } from 'vitest'
import { MIN_SEED_ROWS, assertSeedFloor } from '../scripts/seed-floor.mjs'

describe('assertSeedFloor', () => {
  it('refuses the empty seed of 2026-11-06', () => {
    expect(() => assertSeedFloor(0)).toThrow(/refusing to publish a seed of 0 address rows/)
  })

  it('refuses a truncated download just under the floor', () => {
    expect(() => assertSeedFloor(MIN_SEED_ROWS - 1)).toThrow(/floor 120000/)
  })

  it('accepts the real registry size', () => {
    expect(() => assertSeedFloor(139_774)).not.toThrow()
    expect(() => assertSeedFloor(MIN_SEED_ROWS)).not.toThrow()
  })

  it('refuses a count that is not a whole number', () => {
    expect(() => assertSeedFloor(Number.NaN)).toThrow()
  })
})
