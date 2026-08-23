// Shared test fixtures and the app factory used by every integration test.
//
// The city is ALWAYS stubbed: `fetch` is injected into createApp, and the test
// suite additionally replaces globalThis.fetch with a thrower so that any code
// path reaching the real network fails the test loudly (rule 1 — never send a
// request to reykjavik.is from tests).

import { readdirSync, readFileSync } from 'node:fs'
import { DatabaseSync } from 'node:sqlite'
import { createApp } from '../../src/app'
import type { Env } from '../../src/env'
import { createRegistry } from '../../src/registry'
import type { AddressPoint, Registry } from '../../src/registry'
import { RegistryNotLoadedError } from '../../src/registry-loader'
import { FakeD1 } from './fake-d1'
import relayRequestJson from '../../../data/relay-request.json'

const RELAY_FIELDS = (relayRequestJson as unknown as { fields: Record<string, unknown> }).fields

// Every migration, in order — the tests build the database the same way D1
// does. Reading only 0001 would mean a table added in a later migration exists
// in production and not in the tests, which is a failure that looks like a
// passing suite.
export const MIGRATION_SQL = readdirSync('migrations')
  .filter((name) => name.endsWith('.sql'))
  .sort()
  .map((name) => readFileSync(`migrations/${name}`, 'utf8'))
  .join('\n')

// Laugavegur 1 is the registry's own coordinate (verified against the HMS
// export to the last decimal — see docs/research/payload-map.md).
export const FIXTURE_ADDRESSES: AddressPoint[] = [
  {
    svfnr: 0,
    streetNf: 'Laugavegur',
    houseNumber: 1,
    houseLetter: null,
    postalCode: '101',
    lat: 64.14658919,
    lng: -21.93279823,
  },
  {
    svfnr: 0,
    streetNf: 'Borgartún',
    houseNumber: 12,
    houseLetter: null,
    postalCode: '105',
    lat: 64.14394,
    lng: -21.9122,
  },
  {
    svfnr: 1000,
    streetNf: 'Hamraborg',
    houseNumber: 3,
    houseLetter: null,
    postalCode: '200',
    lat: 64.1109,
    lng: -21.901,
  },
]

export const REYKJAVIK_POINT = { latitude: '64.14658919', longitude: '-21.93279823' }
export const KOPAVOGUR_POINT = { latitude: '64.1109', longitude: '-21.901' }

/** A token that passes the live-send shape check (≥32 chars of [A-Za-z0-9_-]). */
export const TEST_LIVE_KEY = 'test-live-key-0123456789abcdef0123456789'

/**
 * A genuine JPEG file (a 1x1 JFIF: SOI, APP0 with the JFIF marker, EOI).
 * Every test that posts a report needs a photo whose bytes match its declared
 * type, because the relay sniffs the bytes behind the MIME type and refuses a
 * mismatch; a fake "jpeg" of arbitrary bytes would fail every other describe
 * block for the wrong reason.
 */
export const JPEG_BYTES = new Uint8Array([
  0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01,
  0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xff, 0xd9,
])

export interface TestAppOptions {
  /** Give env a CITY_SEND_KEY so the relay attempts the live city POST. */
  live?: boolean
  registry?: Registry
  /** Throw from getRegistry (simulates an unseeded addresses table). */
  registryError?: boolean
  cityFetch?: (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>
}

export interface TestApp {
  app: (request: Request) => Promise<Response>
  sqlite: DatabaseSync
  env: Env
  cityFetch: (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>
}

export function createTestApp(options: TestAppOptions = {}): TestApp {
  const sqlite = new DatabaseSync(':memory:')
  sqlite.exec(MIGRATION_SQL)
  const db = new FakeD1(sqlite) as unknown as D1Database

  const cityFetch =
    options.cityFetch ??
    (() => {
      throw new Error('unexpected city fetch in this test')
    })

  const env: Env = {
    DB: db,
    ...(options.live ? { CITY_SEND_KEY: TEST_LIVE_KEY } : {}),
  }

  const app = createApp(env, {
    fetch: cityFetch,
    getRegistry: () => {
      if (options.registryError) throw new RegistryNotLoadedError()
      return Promise.resolve(options.registry ?? createRegistry(FIXTURE_ADDRESSES))
    },
    now: () => '2026-08-21T12:00:00.000Z',
    randomId: () => 'a1b2c3d4e5f60718',
  })

  return { app, sqlite, env, cityFetch }
}

/** A report in the app's vocabulary, as a multipart body built from the contract. */
export function reportForm(overrides: Record<string, string> = {}): FormData {
  const fd = new FormData()
  // Values bound by role; the wire name of each part is the contract's own
  // key, so a field renamed in data/relay-request.json fails these tests
  // instead of silently changing what goes over the wire.
  const values: Record<string, string | File> = {
    category: 'ruslafotur',
    latitude: REYKJAVIK_POINT.latitude,
    longitude: REYKJAVIK_POINT.longitude,
    description: 'Full ruslafata við stíginn',
    photo: new File([JPEG_BYTES], 'bin.jpg', { type: 'image/jpeg' }),
  }
  for (const name of Object.keys(RELAY_FIELDS)) {
    const value = values[name]
    if (value !== undefined) fd.append(name, value)
  }
  for (const [key, value] of Object.entries(overrides)) {
    if (value === '__remove__') {
      fd.delete(key)
    } else {
      fd.set(key, value)
    }
  }
  return fd
}

export async function postReport(app: (request: Request) => Promise<Response>, fd: FormData) {
  return app(new Request('https://relay.local/api/reports', { method: 'POST', body: fd }))
}

export function json(response: Response): Promise<Record<string, unknown>> {
  return response.json()
}
