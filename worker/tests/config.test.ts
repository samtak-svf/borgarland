// The live-send gate, resolved (#168).
//
// These tests are about the control rather than about what happens past it.
// Two properties are load-bearing and neither is provable by reading the code
// once: that the absence of all configuration is OFF, and that the states which
// used to be silent — a switch turned on over a secret that cannot arm it —
// each read as themselves rather than collapsing into "off".
//
// The gate's refusals are all fail-closed, so a test that got a state wrong
// would still see nothing sent. That is exactly why they are asserted on the
// readout and not only on behaviour: a gate that refuses for the wrong reason
// is a gate nobody can operate.

import { describe, expect, it } from 'vitest'
import { isDryRun, isLiveSendEnabled, resolveLiveSend } from '../src/config'
import type { Env } from '../src/env'

const STRONG_KEY = 'test-live-key-0123456789abcdef0123456789'

function gate(bindings: Partial<Pick<Env, 'LIVE_SEND' | 'CITY_SEND_KEY'>>) {
  return resolveLiveSend(bindings as Pick<Env, 'LIVE_SEND' | 'CITY_SEND_KEY'>)
}

describe('doing nothing is off', () => {
  it('resolves an empty environment to off, and says so in every field', () => {
    expect(gate({})).toEqual({ state: 'off', switch: 'off', key: 'absent' })
  })

  it('is dry run with no configuration at all', () => {
    expect(isDryRun({} as Env)).toBe(true)
    expect(isLiveSendEnabled({} as Env)).toBe(false)
  })

  it('stays off when the capability is present and the switch was never flipped', () => {
    // The half that is strictly new. Before #168 this environment SENT: a
    // strong key was the whole gate, so a secret that outlived the moment it
    // was put for kept arming every request. Now the key is a capability and
    // the switch has to be on as well.
    expect(gate({ CITY_SEND_KEY: STRONG_KEY })).toEqual({
      state: 'off',
      switch: 'off',
      key: 'valid',
    })
    expect(isDryRun({ CITY_SEND_KEY: STRONG_KEY } as Env)).toBe(true)
  })
})

describe('both halves, and only both, arm it', () => {
  it('is armed with the switch on and a strong key', () => {
    expect(gate({ LIVE_SEND: 'on', CITY_SEND_KEY: STRONG_KEY })).toEqual({
      state: 'armed',
      switch: 'on',
      key: 'valid',
    })
    expect(isLiveSendEnabled({ LIVE_SEND: 'on', CITY_SEND_KEY: STRONG_KEY } as Env)).toBe(true)
  })

  it('reads the switch through surrounding whitespace and case', () => {
    // A var edited by hand in a JSON file. Being forgiving here costs nothing:
    // the capability secret is what actually gates the send.
    expect(gate({ LIVE_SEND: '  ON  ', CITY_SEND_KEY: STRONG_KEY }).state).toBe('armed')
  })
})

describe('a switch that is on and cannot send says which half is missing', () => {
  it('reports key-missing rather than off when there is no secret', () => {
    // The state a stray "on" reaching an environment with no secret produces.
    // It must not look like somebody deliberately turned the relay off.
    expect(gate({ LIVE_SEND: 'on' })).toEqual({
      state: 'key-missing',
      switch: 'on',
      key: 'absent',
    })
    expect(isDryRun({ LIVE_SEND: 'on' } as Env)).toBe(true)
  })

  it('reports key-refused when the secret is set but fails the shape check', () => {
    // The state the old gate could not express at all, and the one most likely
    // to be a mistake: somebody ran `wrangler secret put CITY_SEND_KEY` and
    // typed "true".
    expect(gate({ LIVE_SEND: 'on', CITY_SEND_KEY: 'true' })).toEqual({
      state: 'key-refused',
      switch: 'on',
      key: 'refused',
    })
    expect(isDryRun({ LIVE_SEND: 'on', CITY_SEND_KEY: 'true' } as Env)).toBe(true)
  })

  it.each([
    ['too short', 'abc123'],
    ['thirty-one characters, one under the floor', 'a'.repeat(31)],
    ['long enough but with a character outside the alphabet', `${'a'.repeat(31)}!`],
    ['empty string, which is a binding that exists and holds nothing', ''],
  ])('refuses a key that is %s', (_why, value) => {
    expect(isLiveSendEnabled({ LIVE_SEND: 'on', CITY_SEND_KEY: value } as Env)).toBe(false)
  })
})

describe('a key that cannot arm is legible before anyone depends on it', () => {
  it('reports the key condition even while the switch is off', () => {
    // The point of reporting `key` separately from `state`. An operator can
    // find out that the secret is unusable at any time, rather than at the
    // moment they flip the switch and nothing happens.
    expect(gate({ LIVE_SEND: 'off', CITY_SEND_KEY: 'true' })).toEqual({
      state: 'off',
      switch: 'off',
      key: 'refused',
    })
  })
})

describe('the switch honours no near-misses', () => {
  it.each(['true', '1', 'yes', 'enabled', 'ON!', 'off '])(
    'does not arm on %j, and reports the position rather than guessing',
    (value) => {
      const readout = gate({ LIVE_SEND: value, CITY_SEND_KEY: STRONG_KEY })
      expect(readout.state).toBe('off')
      // "off " is a recognised off with whitespace; the rest are not values
      // this switch has, and are reported as such so a typo is visible.
      expect(readout.switch).toBe(value.trim().toLowerCase() === 'off' ? 'off' : 'unrecognised')
    },
  )

  it('treats an empty var the way it treats an absent one', () => {
    expect(gate({ LIVE_SEND: '', CITY_SEND_KEY: STRONG_KEY }).switch).toBe('off')
  })

  it('treats a non-string binding as off', () => {
    // Bindings arrive from the platform, not from TypeScript.
    expect(gate({ LIVE_SEND: true as unknown as string }).switch).toBe('off')
  })
})

describe('the readout is safe to serialise', () => {
  it('names conditions and never echoes either binding', () => {
    const serialised = JSON.stringify(gate({ LIVE_SEND: 'on', CITY_SEND_KEY: STRONG_KEY }))
    expect(serialised).not.toContain(STRONG_KEY)
  })
})
