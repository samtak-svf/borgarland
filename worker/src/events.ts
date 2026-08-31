// The client event stream, and the allowlist that is its privacy boundary.
//
// The apps tell the relay what happened while someone filed a report:
// permissions, how long the coordinate took, how accurate it was, which
// category was chosen, how long the description ran, whether the send left the
// phone. None of that was visible before, and a send that never happened was
// indistinguishable from one that failed silently.
//
// EVERYTHING HERE IS A REFUSAL BY DEFAULT. An unknown event name, an unknown
// field, a field of the wrong type, a string where a number belongs: all 400.
// That is not defensive style, it is the mechanism that makes this channel
// incapable of carrying content. data/relay-events.json names no free-text
// field anywhere, so the description, the coordinate, the photo and the email
// have nowhere to go even if an app tried to send them. Adding a string field
// to that file is a privacy decision, not a schema change.

import { HttpError } from './domain'
import { isKnownCategory } from './adapters/reykjavik'
import eventsContractJson from '../../data/relay-events.json'

interface EventSpec {
  fields: Record<string, string | string[]>
}

interface EventsContract {
  endpoint: { path: string; method: string; contentType: string }
  envelope: { platform: { enum: string[] }; events: { maxLength: number } }
  events: Record<string, EventSpec>
}

const CONTRACT = eventsContractJson as unknown as EventsContract

export const EVENTS_PATH: string = CONTRACT.endpoint.path

const EVENT_SPECS: Record<string, EventSpec> = CONTRACT.events
const PLATFORMS: ReadonlySet<string> = new Set(CONTRACT.envelope.platform.enum)
const MAX_EVENTS: number = CONTRACT.envelope.events.maxLength

/** Fresh per app LAUNCH, so it groups a sitting and cannot follow a person. */
export const SESSION_PATTERN = /^[0-9a-f]{32}$/

/**
 * The app's own version string. Constrained rather than accepted as free text:
 * it is the only string in the envelope, so it is the only place content could
 * be smuggled through an otherwise numeric channel.
 */
const APP_VERSION_PATTERN = /^[0-9A-Za-z.()+\- ]{1,40}$/

/** A day in milliseconds. An offset beyond this is a broken clock, not a session. */
const MAX_AT_MS = 86_400_000

export interface ValidatedEvent {
  name: string
  atMs: number
  fields: Record<string, string | number | boolean>
}

export interface ValidatedBatch {
  session: string
  platform: string
  appVersion: string
  events: ValidatedEvent[]
}

function bad(reason: string, extra: Record<string, unknown> = {}): never {
  throw new HttpError(400, 'invalid-event-batch', { reason, ...extra })
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function readInteger(value: unknown, field: string): number {
  // No coercion: '5' and 5.5 and NaN are all refused, the same way the report
  // path refuses a coerced coordinate (domain.ts).
  if (typeof value !== 'number' || !Number.isSafeInteger(value)) {
    bad('field must be a whole number', { field })
  }
  if (value < 0 || value > MAX_AT_MS) {
    bad('field out of range', { field })
  }
  return value
}

function validateField(
  eventName: string,
  field: string,
  spec: string | string[],
  value: unknown,
): string | number | boolean {
  if (Array.isArray(spec)) {
    if (typeof value !== 'string' || !spec.includes(value)) {
      bad('field must be one of the values the contract names', { event: eventName, field })
    }
    return value
  }
  if (spec === 'boolean') {
    if (typeof value !== 'boolean') bad('field must be a boolean', { event: eventName, field })
    return value
  }
  if (spec === 'integer') {
    return readInteger(value, field)
  }
  if (spec === 'categorySlug') {
    // Our own vocabulary, and the adapter is the only module that knows the
    // city's slugs (AGENTS.md), so this asks it rather than keeping a copy.
    if (typeof value !== 'string' || !isKnownCategory(value)) {
      bad('field must be a known category slug', { event: eventName, field })
    }
    return value
  }
  // An unrecognised spec in the contract file is a bug in the contract, not in
  // the request. Refuse rather than let an unvalidated value through.
  bad('the contract names a field type this relay cannot validate', { event: eventName, field })
}

function validateEvent(raw: unknown): ValidatedEvent {
  if (!isPlainObject(raw)) bad('each event must be an object')

  const name = raw.name
  if (typeof name !== 'string' || !Object.prototype.hasOwnProperty.call(EVENT_SPECS, name)) {
    bad('unknown event name', { name: typeof name === 'string' ? name : null })
  }
  const spec = EVENT_SPECS[name as string]
  const atMs = readInteger(raw.atMs, 'atMs')

  const fields: Record<string, string | number | boolean> = {}
  for (const key of Object.keys(raw)) {
    if (key === 'name' || key === 'atMs') continue
    if (!Object.prototype.hasOwnProperty.call(spec.fields, key)) {
      // The whole point. A part the contract does not name is refused, never
      // stored and never silently dropped.
      bad('this event does not carry that field', { event: name as string, field: key })
    }
    fields[key] = validateField(name as string, key, spec.fields[key], raw[key])
  }
  for (const required of Object.keys(spec.fields)) {
    if (!(required in fields)) {
      bad('event is missing a field the contract requires', {
        event: name as string,
        field: required,
      })
    }
  }

  return { name: name as string, atMs, fields }
}

export function validateBatch(body: unknown): ValidatedBatch {
  if (!isPlainObject(body)) bad('body must be a JSON object')

  const { session, platform, appVersion, events } = body

  if (typeof session !== 'string' || !SESSION_PATTERN.test(session)) {
    bad('session must be 32 lowercase hex characters')
  }
  if (typeof platform !== 'string' || !PLATFORMS.has(platform)) {
    bad('unknown platform')
  }
  if (typeof appVersion !== 'string' || !APP_VERSION_PATTERN.test(appVersion)) {
    bad('appVersion is not a version string')
  }
  if (!Array.isArray(events) || events.length === 0) {
    bad('events must be a non-empty array')
  }
  if (events.length > MAX_EVENTS) {
    // Refused rather than truncated: a silently shortened batch is a timeline
    // with a hole in it that nothing reports.
    bad('too many events in one batch', { max: MAX_EVENTS, got: events.length })
  }

  for (const key of Object.keys(body)) {
    if (!['session', 'platform', 'appVersion', 'events'].includes(key)) {
      bad('the envelope does not carry that field', { field: key })
    }
  }

  return {
    session,
    platform,
    appVersion,
    events: events.map(validateEvent),
  }
}
