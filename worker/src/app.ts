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
//   5. build the would-be payload, store the photographs, record the row
//      marked dry_run, and return the payload. ALWAYS. There is no sixth step
//      and no branch: a report cannot reach the city by arriving, whatever the
//      configuration says (decision 0017).
//
// The city is reached by one path, which is not this one:
//
//   POST /api/reports/:id/promote   Authorization: Bearer <CITY_SEND_KEY>
//
// an operator act on a report that is already stored. This header said
// otherwise for three hours after #182 removed the branch it described — the
// body comments were updated and the header above them was not, in the same
// file, by the same change.

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
import { isDryRun, isLiveSendEnabled, resolveLiveSend } from './config'
import {
  claimLiveReport,
  completeLiveReport,
  getReport,
  insertClientEvents,
  insertReport,
  isDuplicateKey,
  readOneSubmission,
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

/**
 * Fields from an HttpError's extra that are safe to keep in a log line.
 *
 * `event` names the allowlisted event a field error was about, so it carries no
 * more than data/relay-events.json already publishes. `name` is the exception
 * and is filtered; see safeEventName.
 */
const LOGGABLE_EXTRA = [
  'svfnr',
  'field',
  'mime',
  'declared',
  'actual',
  'reason',
  'event',
  'name',
] as const

// `name` is the one client-controlled string that reaches a log line, and #140
// had this backwards: it called an event name "from a fixed allowlist, not free
// text". That is true of `event` and false of `name`, because the only throw
// carrying `name` is the one saying the name is UNKNOWN — so by construction
// the allowlist did not match it.
//
// It is still the single most useful thing to log. One unknown name refuses the
// whole batch, the app drops a 4xx without retrying, and the report travels on
// a separate handler and succeeds, so the person filing sees success and the
// log is the only place that loss is ever visible.
//
// Hence filtered rather than trusted. A real event name is kebab-case ASCII and
// survives untouched; anything else is mangled to dots and bounded, so a
// description or a coordinate cannot ride this field into the logs even if some
// future client puts one there.
const MAX_LOGGED_NAME = 40

function safeEventName(value: unknown): string | null {
  if (typeof value !== 'string') return null
  return value.slice(0, MAX_LOGGED_NAME).replace(/[^a-z0-9-]/gi, '.')
}

function safeExtra(extra: Record<string, unknown> | undefined): Record<string, unknown> {
  if (extra === undefined) return {}
  const out: Record<string, unknown> = {}
  for (const key of LOGGABLE_EXTRA) {
    if (!(key in extra)) continue
    out[key] = key === 'name' ? safeEventName(extra[key]) : extra[key]
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

    // Which build filed this report, from the app's own User-Agent (#128) —
    // deliberately not the raw header: a raw UA would carry the device model,
    // which is exactly what #128 replaced, and the events contract records the
    // version and nothing else. A sender that is not the app stores nothing
    // (#186).
    const userAgent = request.headers.get('User-Agent') ?? ''
    const appVersion = /^Borgarland\/(.+)$/.exec(userAgent)?.[1] ?? null

    // What each photo declared it was and what its bytes actually were, kept
    // on the row for diagnosis (#186). The guard below guarantees they match
    // for everything that reaches this point; the pair is recorded anyway,
    // because the day that guard changes is the day this column starts
    // telling us something.
    const photoMimes: { declared: string; actual: string }[] = []
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
      photoMimes.push({ declared: part.type, actual: actual ?? part.type })
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

    // No gate is consulted here any more, and that is the point of #181.
    //
    // A report can no longer go to the city by arriving. It is stored, always,
    // as a dry run; the live submission is an operator act on a stored row
    // (POST /api/reports/:id/promote). So there is nothing in this request a
    // buggy or malicious client could send to reach the city — not a field, not
    // a header, not an id. The property config.ts has always claimed is now
    // structural rather than argued.
    //
    // It also removes the failure #178 was filed about: an armed relay used to
    // answer 409 live-send-already-used to every tester who walked once the one
    // was spent. Everyone gets an ordinary dry run now, whatever the switch says.
    const draft: ReportDraft = {
      category,
      latitude,
      longitude,
      description: composeDescription(description, jurisdiction.nearest, maxDescriptionLength),
      email,
      photos,
    }

    const createdAt = now()

    // What would have gone over the wire — built before the row so the stored
    // copy can be part of the row (#186).
    const payload = buildCityPayload(draft)

    // The copy the row keeps (#186): what would have gone over the wire, with
    // the email removed. 0004 dropped the email column because the relay keeps
    // no address — "the most sensitive thing in the request" — and a stored
    // payload that carried it would be a second store of the same thing in the
    // same table. Photo bytes are already summarized away by publicPayload.
    const publicCopy = publicPayload(payload)
    const { email: _email, ...fieldsWithoutEmail } = publicCopy.fields
    const storedPayload: Record<string, unknown> = { ...publicCopy, fields: fieldsWithoutEmail }

    // How far the nearest registered address was — #31's question, and
    // previously reachable only through the refusal path's log line (#186).
    const jurisdictionKm = Math.round(jurisdiction.km * 100) / 100

    const base: Omit<NewReport, 'dryRun' | 'sentAt' | 'cityStatus' | 'cityReference' | 'rejection'> = {
      // The app's id when it sent one, so the row IS the report the app is
      // talking about and a repeat finds it. Otherwise ours, as before.
      id: suppliedReportId === '' ? randomId() : suppliedReportId,
      category,
      latitude,
      longitude,
      description: draft.description,
      // No email. It is on the draft above, bound for the city, and the row
      // deliberately has nowhere to put it (#163, migration 0004).
      photoCount: photos.length,
      photoBytes: photos.reduce((sum, p) => sum + p.size, 0),
      createdAt,
      appVersion,
      photoMimes,
      cityPayload: storedPayload,
      jurisdictionKm,
    }

    // Kept so the report can be REVIEWED before anybody decides it is worth
    // filing for real (#181): a category and a coordinate are not enough to
    // make that call. Written before the row, so a stored row never points at
    // photographs that are not there.
    //
    // Thirty days, enforced by a lifecycle rule on the bucket rather than by
    // code — see wrangler.jsonc. The address is still stored nowhere: it is
    // supplied again at promote time, one value, for the one report.
    await Promise.all(
      photos.map((photo, index) =>
        env.PHOTOS.put(`${base.id}/${index}`, photo.bytes, {
          httpMetadata: { contentType: photo.mime },
          customMetadata: { name: photo.name, reportId: base.id },
        }),
      ),
    )

    {
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

  }

  /**
   * The operator, or nobody. Constant-time, because a compare that returns
   * early leaks the prefix one request at a time.
   *
   * BOTH halves of the gate are required, exactly as they were when a report
   * could go live on arrival: the switch says whether this relay is meant to
   * reach the city at all, and the key is the capability. A key on its own
   * promotes nothing, so leaving the secret in place between occasions is not
   * an armed relay.
   */
  function requireOperator(request: Request): void {
    if (!isLiveSendEnabled(env)) {
      throw new HttpError(409, 'live-send-not-armed', {
        reason:
          'the LIVE_SEND switch is off or the CITY_SEND_KEY is missing or malformed; ' +
          'GET /api/health reports which',
      })
    }
    const header = request.headers.get('Authorization') ?? ''
    const offered = header.startsWith('Bearer ') ? header.slice(7) : ''
    const expected = env.CITY_SEND_KEY ?? ''
    let mismatch = offered.length === expected.length ? 0 : 1
    for (let i = 0; i < Math.max(offered.length, expected.length); i++) {
      mismatch |= offered.charCodeAt(i % (offered.length || 1)) ^ expected.charCodeAt(i % (expected.length || 1))
    }
    if (mismatch !== 0) throw new HttpError(401, 'not-the-operator')
  }

  /**
   * Look at a stored photograph, as the operator.
   *
   * Promotion is a judgement about whether an ábending is worth filing with the
   * city, and that judgement cannot be made from a category and a coordinate.
   * This is the only way to see the evidence, and it is behind the operator
   * credential: the photographs are other people's.
   */
  async function handlePhoto(id: string, index: string, request: Request): Promise<Response> {
    requireOperator(request)
    const object = await env.PHOTOS.get(`${id}/${index}`)
    if (object === null) throw new HttpError(404, 'photo-not-found')
    return new Response(object.body, {
      headers: {
        'content-type': object.httpMetadata?.contentType ?? 'application/octet-stream',
        'cache-control': 'no-store',
      },
    })
  }

  /**
   * Decision 0006's one real submission, taken on purpose, on a report that is
   * already stored (#181).
   *
   * This is the ONLY path in the relay that posts to the city. It is not
   * reachable by anything a reporting client sends: it needs a credential no
   * app holds and cannot read, on a report that already exists. That is the
   * difference from every scoping design considered before it — an identity in
   * the request, however unguessable, is still a value the client carries, and
   * on an unauthenticated endpoint carrying a value and claiming it are the
   * same bytes.
   *
   * The address is supplied here rather than read from the row, because the row
   * deliberately has nowhere to put one (#163, migration 0004, decision 0015).
   * One value, typed once, for the one report — the relay still holds no
   * register of addresses. The photographs come from R2, because they cannot be
   * typed.
   */
  async function handlePromote(id: string, request: Request): Promise<Response> {
    requireOperator(request)

    const stored = await getReport(db, id)
    if (stored === null) throw new HttpError(404, 'not-found')
    if (!stored.dryRun) {
      // Already the one. Answering with the row rather than refusing: promoting
      // the same report twice is a finger slipping, not a second submission.
      return json({ report: stored, alreadyLive: true }, 200)
    }

    let form: FormData
    try {
      form = await request.formData()
    } catch {
      throw new HttpError(400, 'invalid-multipart', { reason: 'the promote body is not multipart form data' })
    }
    const emailValue = form.get('email')
    const email = typeof emailValue === 'string' ? emailValue.trim() : ''
    if (email === '') {
      throw new HttpError(400, 'email-required', {
        reason:
          'the city answers a report by email and by nothing else, and the relay stores none — ' +
          'supply the address the reporter filed with',
      })
    }

    // The photographs the person actually took, read back from the store. Not
    // re-supplied by the operator: a photograph that travelled through a chat
    // app is re-encoded, and the city would then receive a different picture
    // from the one the report was filed about.
    const photos: ReportDraft['photos'] = []
    for (let index = 0; index < stored.photoCount; index++) {
      const object = await env.PHOTOS.get(`${id}/${index}`)
      if (object === null) {
        throw new HttpError(410, 'photo-expired', {
          reason: `photograph ${index} is no longer stored; the bucket expires objects after 30 days`,
          photoCount: stored.photoCount,
        })
      }
      const bytes = new Uint8Array(await object.arrayBuffer())
      photos.push({
        name: object.customMetadata?.name ?? `mynd-${index}.jpg`,
        mime: object.httpMetadata?.contentType ?? 'image/jpeg',
        bytes,
        size: bytes.byteLength,
      })
    }

    const payload = buildCityPayload({
      category: stored.category,
      latitude: stored.latitude,
      longitude: stored.longitude,
      // Already composed when the report was filed, address line and all. Not
      // recomposed here, or the crew's line would be appended twice.
      description: stored.description,
      email,
      photos,
    })

    const claim = await claimLiveReport(db, id)
    if (claim.status === 'not-found') throw new HttpError(404, 'not-found')
    if (claim.status === 'already-live') return json({ report: claim.report, alreadyLive: true }, 200)
    if (claim.status === 'gate-closed') {
      throw new HttpError(409, 'live-send-already-used', {
        reason:
          'this relay has already made its one deliberate real submission (decision 0006); ' +
          'sending another is a code change, not a configuration change',
      })
    }

    let outcome: CitySubmitOutcome
    try {
      outcome = await submitCityPayload(payload, doFetch)
    } catch {
      // The one stays spent, deliberately: a throw cannot distinguish a request
      // that never left from one whose answer was lost.
      const record = await completeLiveReport(db, id, {
        sentAt: null,
        cityStatus: null,
        cityReference: null,
        rejection: 'error',
      })
      logEvent({ kind: 'promote', outcome: 'city-unreachable', id })
      return json({ error: 'city-unreachable', report: record }, 502)
    }

    const record = await completeLiveReport(db, id, {
      sentAt: now(),
      cityStatus: outcome.status === 'accepted' ? 200 : outcome.httpStatus,
      cityReference: outcome.status === 'accepted' ? outcome.reference : null,
      rejection: outcome.status === 'rejected' ? outcome.reason : outcome.status === 'error' ? 'error' : null,
    })

    logEvent({
      kind: 'promote',
      outcome: outcome.status,
      id,
      cityStatus: record.cityStatus,
      cityReference: record.cityReference,
    })

    if (outcome.status === 'accepted') return json({ report: record }, 200)
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
        // The one thing an operator most needs to know, and the reason this
        // endpoint is the switch's readout: dryRun is the consequence, and
        // liveSend is the control that produced it — which way the switch is
        // set, what condition the capability secret is in, and therefore
        // whether "on" would actually send. Conditions only; no value of
        // either binding is echoed (#168).
        dryRun: isDryRun(env),
        liveSend: resolveLiveSend(env),
        // The state health could not see until #181, and the one that made an
        // armed relay look fine while it would have refused everything: whether
        // decision 0006's one has been taken. `armed` says a promote is
        // permitted; this says whether one would still succeed.
        oneSubmission: await readOneSubmission(db),
        registry,
      },
      loaded ? 200 : 503,
    )
  }

  const db = env.DB

  return async function handler(request: Request): Promise<Response> {
    // Which route is answering, so the catch below can say so.
    //
    // Every handler throws HttpError into this one catch, which used to
    // hardcode `kind: 'report'`. A refused events batch therefore produced a
    // line claiming to be about a report, and that is the endpoint it is least
    // affordable on: validateBatch throws before handleEvents' own logEvent
    // runs, the app treats 4xx as REJECTED and drops the batch without
    // retrying, and the report goes through on a separate handler. The person
    // filing sees success and the log is the only remaining witness (#140).
    //
    // Assigned by the router as it dispatches rather than derived from the path
    // a second time, because a second path table is a second thing to keep in
    // step with this one.
    let kind = 'unknown'
    try {
      const path = new URL(request.url).pathname

      if (path === EVENTS_PATH) {
        kind = 'events'
        if (request.method === 'POST') return await handleEvents(request)
        return json({ error: 'method-not-allowed' }, 405)
      }

      if (path === '/api/health') {
        kind = 'health'
        if (request.method === 'GET') return await handleHealth()
        return json({ error: 'method-not-allowed' }, 405)
      }

      if (path === RELAY.endpoint.path) {
        kind = 'report'
        if (request.method === 'POST') return await createReport(request)
        return json({ error: 'method-not-allowed' }, 405)
      }

      const promoteMatch = path.match(/^\/api\/reports\/([^/]+)\/promote$/)
      if (promoteMatch) {
        kind = 'promote'
        if (request.method === 'POST') return await handlePromote(promoteMatch[1], request)
        return json({ error: 'method-not-allowed' }, 405)
      }

      const photoMatch = path.match(/^\/api\/reports\/([^/]+)\/photo\/(\d+)$/)
      if (photoMatch) {
        kind = 'photo'
        if (request.method === 'GET') return await handlePhoto(photoMatch[1], photoMatch[2], request)
        return json({ error: 'method-not-allowed' }, 405)
      }

      const outcomeMatch = path.match(/^\/api\/reports\/([^/]+)\/outcome$/)
      if (outcomeMatch) {
        kind = 'outcome'
        if (request.method === 'POST') return await handleOutcome(outcomeMatch[1], request)
        return json({ error: 'method-not-allowed' }, 405)
      }

      const getMatch = path.match(/^\/api\/reports\/([^/]+)$/)
      if (getMatch) {
        kind = 'report'
        if (request.method === 'GET') return await handleGet(getMatch[1])
        return json({ error: 'method-not-allowed' }, 405)
      }

      return json({ error: 'not-found' }, 404)
    } catch (error) {
      if (error instanceof HttpError) {
        logEvent({
          kind,
          outcome: 'refused',
          code: error.code,
          status: error.status,
          ...safeExtra(error.extra),
        })
        return json({ error: error.code, ...error.extra }, error.status)
      }
      if (error instanceof RegistryNotLoadedError) {
        logEvent({ kind, outcome: 'refused', code: 'registry-not-loaded', status: 503 })
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
