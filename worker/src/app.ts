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
import { postcodeLookup } from 'iceaddr-ts/postcodes'
import { checkJurisdiction, MAX_NEAREST_ADDRESS_KM } from './jurisdiction'
import type { CityPayload, CitySubmitOutcome } from './adapters/reykjavik'
import { buildCityPayload, isKnownCategory, submitCityPayload } from './adapters/reykjavik'
import { isDryRun } from './config'
import {
  completeLiveReport,
  getReport,
  reserveLiveReport,
  insertClientEvents,
  insertReport,
  isDuplicateKey,
  setOutcome,
} from './db'
import { sniffImageFormat } from './image-format'
import { RegistryNotLoadedError, readRegistryHealth } from './registry-loader'
import { EVENTS_PATH, validateBatch } from './events'
import relayRequestJson from '../../data/relay-request.json'

// ---------------------------------------------------------------------------
// The relay request contract. data/relay-request.json is the one place the
// multipart field names live, and everything the relay reads from a request
// is validated against it. The city's vocabulary — type, summary, the display
// name, lat/lng, files — is deliberately absent here: a stale app that still
// sends it gets a 400 (unknown-field) instead of being silently ignored, and
// scripts/check-relay-contract.mjs pins the parts of this contract that
// restate city facts (the description limit, the photo MIME list) to
// data/reykjavik-form.json.
// ---------------------------------------------------------------------------

interface RelayFieldSpec {
  required: boolean
  maxLength?: number
  accept?: string[]
}

interface RelayRequestContract {
  endpoint: { path: string; method: string; contentType: string }
  fields: {
    category: RelayFieldSpec
    latitude: RelayFieldSpec
    longitude: RelayFieldSpec
    description: RelayFieldSpec & { maxLength: number }
    email: RelayFieldSpec
    photo: RelayFieldSpec & { accept: string[] }
  }
}

const RELAY = relayRequestJson as unknown as RelayRequestContract

/** The part names a request may carry, from the contract. Anything else is a 400. */
const KNOWN_FIELD_NAMES: ReadonlySet<string> = new Set(Object.keys(RELAY.fields))

/**
 * The app's own id for a report: 32 lowercase hex, the same shape the relay
 * generates for a report that arrives without one.
 */
const REPORT_ID = /^[0-9a-f]{32}$/

/** The description limit, from the contract (pinned to the city's by the contract check). */
const maxDescriptionLength: number = RELAY.fields.description.maxLength

/** Photo MIME types the relay accepts, from the contract (pinned to the city's list). */
const acceptedPhotoMimes: ReadonlySet<string> = new Set(RELAY.fields.photo.accept)

export interface AppDeps {
  /** The outbound fetch — the only path to the city. Tests stub this. */
  fetch: typeof fetch
  /** Supplies the address registry for the jurisdiction check. */
  getRegistry: () => Promise<Registry>
  /** Injectable clock and id generator, for deterministic tests. */
  now?: () => string
  randomId?: () => string
}

// ---------------------------------------------------------------------------
// One structured line per outcome, for Workers Logs (enabled in
// wrangler.jsonc). This exists because the relay's D1 record is deliberately
// incomplete as a picture of a field test: a refused report is never inserted,
// so the jurisdiction check rejecting a coordinate — the single most
// interesting thing that can happen to a tester in the field — left no trace
// anywhere at all.
//
// What is deliberately NOT logged: the description, the email, and the raw
// coordinate. Those are the reporter's, the privacy policy is still open (#5),
// and none of them are needed to answer the questions a field test asks. The
// municipality code and the postcode are enough to tell a correct refusal from
// a registry bug, which is what we would actually be looking at. A MIME type
// is metadata about the failed upload, not the reporter's, and the
// declared-versus-actual pair is precisely what tells a field test that an
// iPhone's HEIC arrived mislabeled.
// ---------------------------------------------------------------------------

/** Fields from an HttpError's extra that are safe to keep in a log line. */
const LOGGABLE_EXTRA = ['svfnr', 'field', 'mime', 'declared', 'actual', 'reason'] as const

function safeExtra(extra: Record<string, unknown> | undefined): Record<string, unknown> {
  if (extra === undefined) return {}
  const out: Record<string, unknown> = {}
  for (const key of LOGGABLE_EXTRA) {
    if (key in extra) out[key] = extra[key]
  }
  return out
}

export function createApp(env: Env, deps: AppDeps): (request: Request) => Promise<Response> {
  const doFetch = deps.fetch
  const now = deps.now ?? (() => new Date().toISOString())
  const randomId = deps.randomId ?? (() => randomHex(16))

  function logEvent(event: Record<string, unknown>): void {
    console.log(JSON.stringify({ at: now(), ...event }))
  }

  async function createReport(request: Request): Promise<Response> {
    let form: FormData
    try {
      form = await request.formData()
    } catch {
      throw new HttpError(400, 'invalid-multipart')
    }

    // Wire-level contract enforcement: a request may carry only the parts the
    // contract names. This is how a stale app that still speaks the city's
    // vocabulary (type, summary, lat, lng, files) fails loudly instead of
    // being ignored field by field.
    for (const name of form.keys()) {
      if (!KNOWN_FIELD_NAMES.has(name)) {
        throw new HttpError(400, 'unknown-field', { field: name })
      }
    }

    // Which report this IS, before anything else is looked at. A repeat is
    // answered with the row we already have, and it is answered BEFORE the
    // category, the coordinate and the jurisdiction are examined: a report the
    // relay has already taken must not be refused on a second press because
    // something else about the request changed (#88).
    //
    // The app cannot tell a double press from a retry and neither can we. What
    // we can do is make the difference not matter.
    const reportIdValue = form.get('reportId')
    const suppliedReportId = typeof reportIdValue === 'string' ? reportIdValue.trim() : ''
    if (suppliedReportId !== '' && !REPORT_ID.test(suppliedReportId)) {
      throw new HttpError(400, 'invalid-report-id', {
        reason: 'a report id is 32 lowercase hex characters',
      })
    }
    if (suppliedReportId !== '') {
      const existing = await getReport(db, suppliedReportId)
      if (existing !== null) {
        logEvent({ kind: 'report', outcome: 'already-stored', id: suppliedReportId })
        // 200 rather than 201: nothing was created this time. The apps read any
        // 2xx as delivered and say so from data/relay-outcomes.json, so the
        // person is told the same true thing either way.
        return json({ report: existing, duplicate: true }, 200)
      }
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
      if (!acceptedPhotoMimes.has(part.type)) {
        throw new HttpError(400, 'invalid-photo', { reason: 'mime not accepted', mime: part.type })
      }
      // The type allowlist is the city's fact, and it only says what the
      // client CLAIMED the file is. The city validates nothing about the
      // bytes behind a declared type, so a HEIC file declared as image/jpeg
      // would pass the check above and then fail the city's own validation —
      // after the report had been recorded as sent. Sniff the leading bytes
      // and refuse a mismatch here, so the reporter finds out before anything
      // is filed. The sniffed type is the diagnosis, never a second source of
      // truth: the declared type must be on the accept list AND match.
      const bytes = new Uint8Array(await part.arrayBuffer())
      const actual = sniffImageFormat(bytes)
      if (actual !== part.type) {
        throw new HttpError(400, 'invalid-photo', {
          reason: 'declared mime does not match the file contents',
          declared: part.type,
          actual: actual ?? null,
        })
      }
      photos.push({
        name: part.name,
        mime: part.type,
        bytes,
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
        // `place` is the postal locality of the nearest registered address,
        // NOT the municipality: the register carries a code (SVFNR) and a
        // postcode, and no name for the sveitarfélag anywhere. The two
        // coincide often enough to be useful and not always, so the sentence
        // the apps build from it says where the nearest ADDRESS is and claims
        // nothing about who administers it (#148). Dative because Icelandic
        // needs one to say "í Hveragerði" / "í Kópavogi", and inventing it in
        // the app would mean declining a place name in Swift and Kotlin twice.
        const place = postcodeLookup(jurisdiction.nearest.postalCode)
        throw new HttpError(400, 'outside-reykjavik', {
          reason: 'this relay only files reports in Reykjavík (SVFNR 0000)',
          nearestAddress: describeAddress(jurisdiction.nearest),
          svfnr: jurisdiction.nearest.svfnr,
          place: place?.nominative ?? null,
          placeDative: place?.dative ?? null,
        })
      }
      throw new HttpError(400, 'jurisdiction-unknown', {
        reason: 'no registered address near enough to this coordinate to say which municipality it is in',
        // How far the nearest one was, when there was one at all. The address
        // itself is deliberately not offered: at this distance it is not a
        // place, it is an artefact of the register covering one country (#75).
        nearestKm: jurisdiction.km === null ? null : Math.round(jurisdiction.km),
        maxKm: MAX_NEAREST_ADDRESS_KM,
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
      // The app's id when it sent one, so the row IS the report the app is
      // talking about and a repeat finds it. Otherwise ours, as before.
      id: suppliedReportId === '' ? randomId() : suppliedReportId,
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
      let record
      try {
        record = await insertReport(db, {
          ...base,
          dryRun: true,
          sentAt: null,
          cityStatus: null,
          cityReference: null,
          rejection: null,
        })
      } catch (error) {
        // The other half of the duplicate check. The lookup above and this
        // insert are separated by the whole validation pipeline, including a
        // 139,360-row scan, so two requests carrying the same id can both find
        // nothing and both arrive here. The primary key decides it; the loser
        // is answered with the row that won rather than with a 500 for a report
        // that is stored.
        const stored = isDuplicateKey(error) ? await getReport(db, base.id) : null
        if (stored === null) throw error
        logEvent({ kind: 'report', outcome: 'already-stored', id: base.id, raced: true })
        return json({ report: stored, duplicate: true }, 200)
      }
      logEvent({
        kind: 'report',
        outcome: 'recorded',
        dryRun: true,
        category,
        photoCount: photos.length,
        photoBytes: base.photoBytes,
        postalCode: jurisdiction.nearest.postalCode,
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

    // ---------------------------------------------------------------------
    // Decision 0006 says ONE real submission, ever, taken on purpose. This is
    // that "one", enforced rather than remembered.
    //
    // The CITY_SEND_KEY secret arms every request for as long as it exists, so
    // between putting it and deleting it a stray curl, a second tap on the send
    // button or a tester opening the app at the wrong moment files a real
    // ábending into a real work queue. Being careful is exactly the safeguard
    // that failed on 2026-08-21 and put report 110474 in front of a crew
    // (docs/incidents/2026-08-21-filed-a-real-report.md).
    //
    // Deliberately hard-coded, not a variable and not a configurable limit: a
    // variable is one typo away from being raised, and lifting this gate should
    // cost a code change and a review — which is precisely what going live for
    // real will be (#6). Delete this block then, on purpose, in its own PR.
    //
    // The gate is a row in D1, because that is the only thing that survives a
    // deploy, a fresh isolate and a re-set secret. It is claimed by WRITING
    // that row, in one statement, BEFORE the city is posted to (#98). Reading
    // a count and writing the row afterwards is two statements, and two
    // requests in flight at once both read zero and both reached the city.
    const reservation = await reserveLiveReport(db, {
      ...base,
      dryRun: false,
      sentAt: null,
      cityStatus: null,
      cityReference: null,
      rejection: null,
    })

    if (reservation.status === 'gate-closed') {
      throw new HttpError(409, 'live-send-already-used', {
        reason:
          'this relay has already made its one deliberate real submission (decision 0006); ' +
          'sending another is a code change, not a configuration change',
      })
    }

    if (reservation.status === 'duplicate') {
      // The same report arriving twice, close enough together that the lookup
      // at the top of this handler found nothing. It already has the one, so
      // the answer is its row rather than a second send.
      logEvent({ kind: 'report', outcome: 'already-stored', id: base.id, raced: true })
      return json({ report: reservation.report, duplicate: true }, 200)
    }

    let outcome: CitySubmitOutcome
    try {
      outcome = await submitCityPayload(payload, doFetch)
    } catch {
      // The city never answered: connection/DNS error or a thrown fetch. The
      // row already exists, so this records the failure on it. The one stays
      // spent, deliberately: a throw cannot distinguish a request that never
      // left from one whose answer was lost.
      const record = await completeLiveReport(db, base.id, {
        sentAt: null,
        cityStatus: null,
        cityReference: null,
        rejection: 'error',
      })
      return json({ error: 'city-unreachable', report: record }, 502)
    }

    const record = await completeLiveReport(db, base.id, {
      sentAt: now(),
      cityStatus: outcome.status === 'accepted' ? 200 : outcome.httpStatus,
      cityReference: outcome.status === 'accepted' ? outcome.reference : null,
      rejection: outcome.status === 'rejected' ? outcome.reason : outcome.status === 'error' ? 'error' : null,
    })

    if (outcome.status === 'accepted') {
      return json({ report: record }, 201)
    }
    return json({ error: 'city-rejected', report: record }, 502)
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

  // The client event stream (data/relay-events.json). This is the half of a
  // field test the relay could not see: everything the app did before it posted
  // a report, including the reports it never got to post.
  //
  // It is instrumentation, so it answers fast and it never becomes a reason a
  // report fails. It is also the one endpoint an app could accidentally put
  // personal data into, which is why validateBatch refuses anything the
  // contract does not name rather than storing it and sorting it out later.
  async function handleEvents(request: Request): Promise<Response> {
    let body: unknown
    try {
      body = await request.json()
    } catch {
      throw new HttpError(400, 'invalid-event-batch', { reason: 'body is not JSON' })
    }
    const batch = validateBatch(body)
    const stored = await insertClientEvents(db, batch, now())
    logEvent({
      kind: 'events',
      outcome: 'recorded',
      session: batch.session,
      platform: batch.platform,
      count: stored,
    })
    return json({ stored }, 202)
  }

  // Operational readout, deliberately not part of data/relay-request.json: that
  // file is the contract for the request an APP sends, and this is not one.
  //
  // It exists because decision 0009 left the registry refresh unowned, and a
  // stale registry degrades the jurisdiction check quietly instead of failing
  // it. An empty registry answers 503 here for the same reason a report does:
  // the relay refuses every submission in that state, so it is not healthy.
  async function handleHealth(): Promise<Response> {
    const registry = await readRegistryHealth(db, now)
    const loaded = registry.rows > 0
    return json(
      {
        status: loaded ? 'ok' : 'registry-not-loaded',
        // Whether the deliberate CITY_SEND_KEY secret is in place. Not a
        // secret itself, and the one thing an operator most needs to know.
        dryRun: isDryRun(env),
        registry,
      },
      loaded ? 200 : 503,
    )
  }

  const db = env.DB

  return async function handler(request: Request): Promise<Response> {
    try {
      const path = new URL(request.url).pathname

      if (path === EVENTS_PATH) {
        if (request.method === 'POST') return await handleEvents(request)
        return json({ error: 'method-not-allowed' }, 405)
      }

      if (path === '/api/health') {
        if (request.method === 'GET') return await handleHealth()
        return json({ error: 'method-not-allowed' }, 405)
      }

      if (path === RELAY.endpoint.path) {
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
        logEvent({
          kind: 'report',
          outcome: 'refused',
          code: error.code,
          status: error.status,
          ...safeExtra(error.extra),
        })
        return json({ error: error.code, ...error.extra }, error.status)
      }
      if (error instanceof RegistryNotLoadedError) {
        logEvent({ kind: 'report', outcome: 'refused', code: 'registry-not-loaded', status: 503 })
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
