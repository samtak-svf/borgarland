// The relay's request handling. Everything above src/adapters/reykjavik.ts
// speaks our own vocabulary (domain.ts); the adapter is the only module that
// knows the city's field names, slugs or URL.
//
// The flow for POST /api/reports:
//   1. parse the multipart body (our field names, `photo` parts)
//   2. validate: category known, coordinate present/finite/WGS84, description,
//      photo MIME types
//   3. jurisdiction: nearest registered address → SVFNR; anything but 0
//      (Reykjavíkurborg) is refused, never filed
//   4. compose the description we send (nearest address line for the crew)
//   5. dry run (the default, see config.ts): build the would-be payload, record
//      the row marked dry_run, return it. No city POST.
//   6. live (only with the deliberate CITY_SEND_KEY secret): POST to the city,
//      record what came back, return our report id either way.

import type { Env } from './env'
import type { NewReport } from './db'
import type { Outcome, Rejection, ReportDraft, ReportRecord } from './domain'
import {
  HttpError,
  assertWgs84,
  composeDescription,
  readCoordinate,
  readDescription,
} from './domain'
import type { Registry } from './registry'
import { describeAddress } from './registry'
import { checkJurisdiction } from './jurisdiction'
import type { CityPayload, CitySubmitOutcome } from './adapters/reykjavik'
import {
  buildCityPayload,
  isAcceptedPhotoMime,
  isKnownCategory,
  maxDescriptionLength,
  submitCityPayload,
} from './adapters/reykjavik'
import { isDryRun } from './config'
import { getReport, insertReport, setOutcome } from './db'
import { RegistryNotLoadedError } from './registry-loader'

export interface AppDeps {
  /** The outbound fetch — the only path to the city. Tests stub this. */
  fetch: typeof fetch
  /** Supplies the address registry for the jurisdiction check. */
  getRegistry: () => Promise<Registry>
  /** Injectable clock and id generator, for deterministic tests. */
  now?: () => string
  randomId?: () => string
}

export function createApp(env: Env, deps: AppDeps): (request: Request) => Promise<Response> {
  const doFetch = deps.fetch
  const now = deps.now ?? (() => new Date().toISOString())
  const randomId = deps.randomId ?? (() => randomHex(16))

  async function createReport(request: Request): Promise<Response> {
    let form: FormData
    try {
      form = await request.formData()
    } catch {
      throw new HttpError(400, 'invalid-multipart')
    }

    const categoryValue = form.get('category')
    const category = typeof categoryValue === 'string' ? categoryValue.trim() : ''
    if (category === '' || !isKnownCategory(category)) {
      throw new HttpError(400, 'unknown-category')
    }

    // Strict parse, never a Number() coercion — see domain.ts. The city would
    // accept a report with no usable coordinate; we reject one instead.
    const latitude = readCoordinate(form.get('latitude'), 'latitude')
    const longitude = readCoordinate(form.get('longitude'), 'longitude')
    assertWgs84(latitude, longitude)

    const description = readDescription(form.get('description'), maxDescriptionLength)

    const emailValue = form.get('email')
    const email = typeof emailValue === 'string' && emailValue.trim() !== '' ? emailValue.trim() : null

    const photos: ReportDraft['photos'] = []
    for (const part of form.getAll('photo')) {
      if (!(part instanceof File)) {
        throw new HttpError(400, 'invalid-photo', { reason: 'photo parts must be files' })
      }
      if (!isAcceptedPhotoMime(part.type)) {
        throw new HttpError(400, 'invalid-photo', { reason: 'mime not accepted', mime: part.type })
      }
      photos.push({
        name: part.name,
        mime: part.type,
        bytes: new Uint8Array(await part.arrayBuffer()),
        size: part.size,
      })
    }

    let registry: Registry
    try {
      registry = await deps.getRegistry()
    } catch (error) {
      if (error instanceof RegistryNotLoadedError) throw error
      throw error
    }

    const jurisdiction = checkJurisdiction(registry, latitude, longitude)
    if (!jurisdiction.ok) {
      if (jurisdiction.reason === 'outside-reykjavik') {
        throw new HttpError(400, 'outside-reykjavik', {
          reason: 'this relay only files reports in Reykjavík (SVFNR 0000)',
          nearestAddress: describeAddress(jurisdiction.nearest),
          svfnr: jurisdiction.nearest.svfnr,
        })
      }
      throw new HttpError(400, 'jurisdiction-unknown', {
        reason: 'no registered address near this coordinate',
      })
    }

    const dryRun = isDryRun(env)
    const draft: ReportDraft = {
      category,
      latitude,
      longitude,
      description: composeDescription(description, jurisdiction.nearest, maxDescriptionLength),
      email,
      photos,
    }

    const createdAt = now()
    const base: Omit<NewReport, 'dryRun' | 'sentAt' | 'cityStatus' | 'cityReference' | 'rejection'> = {
      id: randomId(),
      category,
      latitude,
      longitude,
      description: draft.description,
      email,
      photoCount: photos.length,
      photoBytes: photos.reduce((sum, p) => sum + p.size, 0),
      createdAt,
    }

    const payload = buildCityPayload(draft)

    if (dryRun) {
      const record = await insertReport(db, {
        ...base,
        dryRun: true,
        sentAt: null,
        cityStatus: null,
        cityReference: null,
        rejection: null,
      })
      return json(
        {
          report: record,
          // What would have gone over the wire. Photo bytes are summarized,
          // not echoed back.
          cityPayload: publicPayload(payload),
        },
        201,
      )
    }

    let outcome: CitySubmitOutcome
    try {
      outcome = await submitCityPayload(payload, doFetch)
    } catch {
      // The city never answered: connection/DNS error or a thrown fetch.
      // Record the failure so the measurement layer sees the attempt.
      const record = await insertReport(db, {
        ...base,
        dryRun: false,
        sentAt: null,
        cityStatus: null,
        cityReference: null,
        rejection: 'error',
      })
      return json({ error: 'city-unreachable', report: record }, 502)
    }

    const record = await insertReport(db, {
      ...base,
      dryRun: false,
      sentAt: now(),
      cityStatus: outcome.status === 'accepted' ? 200 : outcome.httpStatus,
      cityReference: outcome.status === 'accepted' ? outcome.reference : null,
      rejection: outcome.status === 'rejected' ? outcome.reason : outcome.status === 'error' ? 'error' : null,
    })

    if (outcome.status === 'accepted') {
      return json({ report: record }, 201)
    }
    return json({ error: 'city rejected the report', report: record }, 502)
  }

  async function handleGet(id: string): Promise<Response> {
    const report = await getReport(db, id)
    if (report === null) throw new HttpError(404, 'not-found')
    return json({ report })
  }

  async function handleOutcome(id: string, request: Request): Promise<Response> {
    let body: unknown
    try {
      body = await request.json()
    } catch {
      throw new HttpError(400, 'invalid-outcome')
    }
    const outcome = (body as { outcome?: unknown }).outcome
    if (outcome !== 'fixed' && outcome !== 'not-fixed') {
      throw new HttpError(400, 'invalid-outcome')
    }
    const changed = await setOutcome(db, id, outcome as Outcome, now())
    if (!changed) throw new HttpError(404, 'not-found')
    const report = await getReport(db, id)
    return json({ report })
  }

  const db = env.DB

  return async function handler(request: Request): Promise<Response> {
    try {
      const path = new URL(request.url).pathname

      if (path === '/api/reports') {
        if (request.method === 'POST') return await createReport(request)
        return json({ error: 'method-not-allowed' }, 405)
      }

      const outcomeMatch = path.match(/^\/api\/reports\/([^/]+)\/outcome$/)
      if (outcomeMatch) {
        if (request.method === 'POST') return await handleOutcome(outcomeMatch[1], request)
        return json({ error: 'method-not-allowed' }, 405)
      }

      const getMatch = path.match(/^\/api\/reports\/([^/]+)$/)
      if (getMatch) {
        if (request.method === 'GET') return await handleGet(getMatch[1])
        return json({ error: 'method-not-allowed' }, 405)
      }

      return json({ error: 'not-found' }, 404)
    } catch (error) {
      if (error instanceof HttpError) {
        return json({ error: error.code, ...error.extra }, error.status)
      }
      if (error instanceof RegistryNotLoadedError) {
        return json({ error: 'registry-not-loaded' }, 503)
      }
      console.error('internal error', error)
      return json({ error: 'internal' }, 500)
    }
  }
}

function publicPayload(payload: CityPayload): Omit<CityPayload, 'photos'> & {
  photos: { name: string; mime: string; size: number }[]
} {
  return {
    ...payload,
    photos: payload.photos.map(({ name, mime, size }) => ({ name, mime, size })),
  }
}

function randomHex(bytes: number): string {
  const buffer = new Uint8Array(bytes)
  crypto.getRandomValues(buffer)
  return Array.from(buffer, (b) => b.toString(16).padStart(2, '0')).join('')
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  })
}
