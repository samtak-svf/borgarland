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
const eventsContract = JSON.parse(readFileSync('../data/relay-events.json', 'utf8'))
const eventsRaw = readFileSync('../data/relay-events.json', 'utf8')

const EXPECTED_FIELD_NAMES = ['reportId', 'category', 'latitude', 'longitude', 'description', 'email', 'photo']
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
  it('names exactly the seven documented fields, in order', () => {
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

  it('enforces every field it says the relay enforces', async () => {
    for (const name of ['category', 'latitude', 'longitude', 'description']) {
      expect(contract.fields[name].required).toBe(true)
      const { app } = createTestApp()
      const response = await postReport(app, reportForm({ [name]: '__remove__' }))
      expect(response.status).toBe(400)
    }

    // The optional parts may be absent: a report with no photo is accepted
    // (the city accepts one without photos; the relay records photoCount 0).
    expect(contract.fields.photo.required).toBe(false)
    const { app } = createTestApp()
    const fd = reportForm()
    fd.delete('photo')
    const response = await postReport(app, fd)
    expect(response.status).toBe(201)
    expect((await json(response)).report).toMatchObject({ photoCount: 0 })
  })

  it('still takes a report with no address, though the contract requires one of the app', async () => {
    // The one field where the app's obligation and the relay's tolerance
    // differ on purpose (#163). `required` in data/relay-request.json is read
    // by the two apps, which refuse to build a body without an address; this
    // file is read here for the unknown-field allowlist alone, and the email
    // is parsed as optional in src/app.ts.
    //
    // That is not laziness, it is the ordering rule from AGENTS.md running in
    // the direction that is easy to miss. Builds 6 and 7 are on testers'
    // phones and send no address at all. A relay that required one would
    // answer 400 to every report they file, and the fix would be an App Store
    // review rather than a deploy. The relay follows once no such build
    // remains, and this test is what has to be deleted to let it.
    expect(contract.fields.email.required).toBe(true)

    const { app } = createTestApp()
    const fd = reportForm()
    expect(fd.get('email')).toBeNull()
    const response = await postReport(app, fd)
    expect(response.status).toBe(201)
  })

  it('takes the address to the city and keeps none of it', async () => {
    // The relay is a conduit for the address, not a store of it (#163,
    // migration 0004). Same rule the photo bytes have had since the first
    // schema: forwarded, and recorded nowhere.
    //
    // The answer is the whole of what a caller can see of a stored report, so
    // an address absent from it is an address absent from the row — and
    // `reports` has no column left that could hold one.
    const { app } = createTestApp()
    const response = await postReport(app, reportForm({ email: 'nafn@example.is' }))
    expect(response.status).toBe(201)

    const body = await json(response)

    // Forwarded: the city's payload carries it, which is the entire purpose —
    // the confirmation mail is what the reporter gets back.
    const cityPayload = body.cityPayload as { fields: Record<string, string | null> }
    expect(cityPayload.fields.email).toBe('nafn@example.is')

    // Kept nowhere: the stored record is the whole of what the relay holds
    // about a report, and it has no address in it. `reports` no longer has a
    // column that could take one, so this cannot regress by an oversight at a
    // call site — it would have to be a migration.
    expect(body.report).not.toHaveProperty('email')
    expect(JSON.stringify(body.report)).not.toContain('nafn@example.is')
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

// ---------------------------------------------------------------------------
// The client event contract gets the same treatment as its sibling, for the
// same reason and one more: it is the only channel in the system that could
// carry instrumentation, so it is the one where a stray string field turns into
// a privacy incident rather than a bug.
// ---------------------------------------------------------------------------

describe('the client event contract', () => {
  it('carries no city vocabulary', () => {
    // `summary` is the trap. It is one of the city's payload field names AND
    // the obvious word for the app's last screen, and naming our screen that
    // would have forced NoCityEndpointTest to be weakened to accommodate it.
    // Ours is called `confirm`.
    for (const name of CITY_FIELD_NAMES) {
      expect(eventsContract.events['screen-left'].fields.screen).not.toContain(name)
    }
    for (const category of facts.categories) {
      expect(eventsRaw).not.toContain(category.category)
      expect(eventsRaw).not.toContain(category.summary)
    }
  })

  it('names no free-text field anywhere, which is the privacy boundary', () => {
    // Every field is either an integer, a boolean, a category slug, or an
    // explicit list of permitted values. A bare string type would be a hole,
    // and the point of this test is that adding one has to be deliberate.
    const allowedScalarTypes = ['integer', 'boolean', 'categorySlug']
    for (const [eventName, spec] of Object.entries(eventsContract.events) as [string, { fields: Record<string, unknown> }][]) {
      for (const [fieldName, type] of Object.entries(spec.fields)) {
        const ok = Array.isArray(type) || allowedScalarTypes.includes(type as string)
        expect(ok, `${eventName}.${fieldName} is "${String(type)}", which is not a bounded type`).toBe(true)
      }
    }
  })

  it('keeps the two contracts on separate endpoints', () => {
    expect(eventsContract.endpoint.path).toBe('/api/events')
    expect(eventsContract.endpoint.path).not.toBe(contract.endpoint.path)
  })
})
