import { describe, expect, it } from 'vitest'
import { createRegistry, describeAddress } from '../src/registry'
import { FIXTURE_ADDRESSES } from './helpers/fixtures'

describe('Registry', () => {
  it('returns the nearest registered address by great-circle distance', () => {
    const registry = createRegistry(FIXTURE_ADDRESSES)
    // A point just south of Laugavegur 1.
    const nearest = registry.nearest(64.1465, -21.9328)
    expect(nearest?.streetNf).toBe('Laugavegur')
    expect(nearest?.svfnr).toBe(0)
  })

  it('picks a different address for a point nearer to it', () => {
    const registry = createRegistry(FIXTURE_ADDRESSES)
    const nearest = registry.nearest(64.1109, -21.901)
    expect(nearest?.streetNf).toBe('Hamraborg')
    expect(nearest?.svfnr).toBe(1000)
  })

  it('returns null when empty', () => {
    expect(createRegistry([]).nearest(64.14, -21.93)).toBeNull()
  })

  it('handles a house letter in the display line', () => {
    expect(
      describeAddress({
        svfnr: 0,
        streetNf: 'Njálsgata',
        houseNumber: 8,
        houseLetter: 'c',
        postalCode: '101',
        lat: 64.1415,
        lng: -21.9324,
      }),
    ).toBe('Njálsgata 8c, 101 Reykjavík')
  })
})
