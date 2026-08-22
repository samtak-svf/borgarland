// The relay request contract (data/relay-request.json) is the one place the
// multipart field names live. These tests prove the wire enforces it: a
// request carrying anything the contract does not name — the city's
// vocabulary from an old app build — is rejected with unknown-field, the
// requiredness in the file matches what the relay enforces, and the file
// agrees with the city facts where it claims to.
//
// The city is stubbed exactly as in relay.test.ts (deps.fetch), and
// globalThis.fetch is replaced with a thrower so no test can reach the real
// network.

import { readFileSync } from 'node:fs'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createTestApp, json, postReport, reportForm } from './helpers/fixtures'

const contract = JSON.parse(readFileSync('../data/relay-request.json', 'utf8'))
const facts = JSON.parse(readFileSync('../data/reykjavik-form.json', 'utf8'))
const contractRaw = readFileSync('../data/relay-request.json', 'utf8')

const EXPECTED_FIELD_NAMES = ['category', 'latitude', 'longitude', 'description', 'email', 'photo']
// The field names the old app used; none of them may appear in the contract.
const CITY_FIELD_NAMES = ['type', 'summary', 'lat', 'lng', 'files']

beforeEach(() => {
  vi.stubGlobal(
    'fetch',
    () => {
      throw new Error('tests must never hit the real network')
    },
  )
})

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('the relay request contract', () => {
  it('names exactly the six documented fields, in order', () => {
    expect(Object.keys(contract.fields)).toEqual(EXPECTED_FIELD_NAMES)
    expect(contract.endpoint).toMatchObject({
      path: '/api/reports',
      method: 'POST',
      contentType: 'multipart/form-data',
    })
  })

  it('carries no city vocabulary: no old-app field name, display name or summary string', () => {
    for (const name of CITY_FIELD_NAMES) {
      expect(Object.keys(contract.fields)).not.toContain(name)
    }
    for (const category of facts.categories) {
      expect(contractRaw).not.toContain(category.category)
      expect(contractRaw).not.toContain(category.summary)
    }
  })

  it('agrees with the city facts where it claims to', () => {
    expect(contract.fields.description.maxLength).toBe(facts.fields.description.maxLength)
    expect(contract.fields.photo.accept).toEqual(facts.fields.files.accept)
  })

  it('requiredness in the file matches what the relay enforces', async () => {
    for (const name of ['category', 'latitude', 'longitude', 'description']) {
      expect(contract.fields[name].required).toBe(true)
      const { app } = createTestApp()
      const response = await postReport(app, reportForm({ [name]: '__remove__' }))
      expect(response.status).toBe(400)
    }
    for (const name of ['email', 'photo']) {
      expect(contract.fields[name].required).toBe(false)
    }

    // The optional parts may be absent: a report with no photo is accepted
    // (the city accepts one without photos; the relay records photoCount 0).
    const { app } = createTestApp()
    const fd = reportForm()
    fd.delete('photo')
    const response = await postReport(app, fd)
    expect(response.status).toBe(201)
    expect((await json(response)).report).toMatchObject({ photoCount: 0 })
  })

  it('rejects any part the contract does not name, with the offending name', async () => {
    for (const name of CITY_FIELD_NAMES) {
      const { app } = createTestApp()
      const fd = reportForm()
      if (name === 'files') {
        fd.append('files', new File([new Uint8Array([1])], 'x.jpg', { type: 'image/jpeg' }))
      } else {
        fd.append(name, 'whatever the old app sent')
      }
      const response = await postReport(app, fd)
      expect(response.status).toBe(400)
      expect(await json(response)).toEqual({ error: 'unknown-field', field: name })
    }
  })

  it('rejects a random part name too', async () => {
    const { app } = createTestApp()
    const fd = reportForm()
    fd.append('some-field-nowhere-in-the-contract', 'x')
    const response = await postReport(app, fd)
    expect(response.status).toBe(400)
    expect((await json(response)).error).toBe('unknown-field')
  })
})
