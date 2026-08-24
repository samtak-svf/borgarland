// The relay's own record of what was sent, when, and what came back. The table
// is defined in migrations/0001_init.sql; the vocabulary here is ours (see
// domain.ts) — the city's field names never reach this layer.

import type { Outcome, Rejection, ReportRecord } from './domain'
import type { ValidatedBatch } from './events'

interface ReportRow {
  id: string
  category_slug: string
  latitude: number
  longitude: number
  description: string
  email: string | null
  photo_count: number
  photo_bytes: number
  dry_run: number
  created_at: string
  sent_at: string | null
  city_status: number | null
  city_reference: string | null
  rejection: Rejection | null
  outcome: Outcome | null
  outcome_at: string | null
}

const COLUMNS =
  'id, category_slug, latitude, longitude, description, email, photo_count, photo_bytes, ' +
  'dry_run, created_at, sent_at, city_status, city_reference, rejection, outcome, outcome_at'

export interface NewReport {
  id: string
  category: string
  latitude: number
  longitude: number
  description: string
  email: string | null
  photoCount: number
  photoBytes: number
  dryRun: boolean
  createdAt: string
  sentAt: string | null
  cityStatus: number | null
  cityReference: string | null
  rejection: Rejection | null
}

export async function insertReport(db: D1Database, report: NewReport): Promise<ReportRecord> {
  await db
    .prepare(
      `INSERT INTO reports (${COLUMNS})
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      report.id,
      report.category,
      report.latitude,
      report.longitude,
      report.description,
      report.email,
      report.photoCount,
      report.photoBytes,
      report.dryRun ? 1 : 0,
      report.createdAt,
      report.sentAt,
      report.cityStatus,
      report.cityReference,
      report.rejection,
      null, // outcome
      null, // outcome_at
    )
    .run()
  return {
    id: report.id,
    category: report.category,
    latitude: report.latitude,
    longitude: report.longitude,
    description: report.description,
    email: report.email,
    photoCount: report.photoCount,
    photoBytes: report.photoBytes,
    dryRun: report.dryRun,
    createdAt: report.createdAt,
    sentAt: report.sentAt,
    accepted: report.cityStatus === null ? null : report.cityStatus === 200,
    cityStatus: report.cityStatus,
    cityReference: report.cityReference,
    rejection: report.rejection,
    outcome: null,
    outcomeAt: null,
  }
}

/**
 * True when a write failed because the row is already there.
 *
 * The duplicate check in createReport is a check-then-act: two requests with the
 * same id can both read nothing and both try to insert. The primary key is what
 * actually makes the id unique, so the loser is recognised here rather than
 * becoming a 500 for a report that IS stored.
 */
export function isDuplicateKey(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error)
  return /UNIQUE constraint failed|PRIMARY KEY|already exists/i.test(message)
}

export async function getReport(db: D1Database, id: string): Promise<ReportRecord | null> {
  const result = await db.prepare(`SELECT ${COLUMNS} FROM reports WHERE id = ?`).bind(id).all()
  const row = result.results?.[0] as unknown as ReportRow | undefined
  return row ? mapRow(row) : null
}

export async function setOutcome(
  db: D1Database,
  id: string,
  outcome: Outcome,
  at: string,
): Promise<boolean> {
  const result = await db
    .prepare('UPDATE reports SET outcome = ?, outcome_at = ? WHERE id = ?')
    .bind(outcome, at, id)
    .run()
  return (result.meta?.changes ?? 0) > 0
}

function mapRow(row: ReportRow): ReportRecord {
  return {
    id: row.id,
    category: row.category_slug,
    latitude: row.latitude,
    longitude: row.longitude,
    description: row.description,
    email: row.email,
    photoCount: row.photo_count,
    photoBytes: row.photo_bytes,
    dryRun: row.dry_run === 1,
    createdAt: row.created_at,
    sentAt: row.sent_at,
    // Null while the city has not answered (dry run, or the POST failed before
    // a response); otherwise whether it answered 200.
    accepted: row.city_status === null ? null : row.city_status === 200,
    cityStatus: row.city_status,
    cityReference: row.city_reference,
    rejection: row.rejection,
    outcome: row.outcome,
    outcomeAt: row.outcome_at,
  }
}

// ---------------------------------------------------------------------------
// Client events. Everything written here has already passed the allowlist in
// events.ts, which is what makes the `fields` JSON safe to store: the contract
// names no free-text field, so there is nothing in it but numbers, booleans and
// values from fixed sets.
// ---------------------------------------------------------------------------


export async function insertClientEvents(
  db: D1Database,
  batch: ValidatedBatch,
  receivedAt: string,
): Promise<number> {
  const statement = db.prepare(
    `INSERT INTO client_events (session, name, at_ms, platform, app_version, fields, received_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
  )
  const bound = batch.events.map((event) =>
    statement.bind(
      batch.session,
      event.name,
      event.atMs,
      batch.platform,
      batch.appVersion,
      JSON.stringify(event.fields),
      receivedAt,
    ),
  )
  // One round trip for the batch. D1's batch is a transaction, so a timeline
  // either lands whole or not at all.
  await db.batch(bound)
  return bound.length
}

/**
 * The result of trying to claim decision 0006's one live submission.
 *
 * `reserved` means this request owns it and may post to the city. `duplicate`
 * means the id is already the relay's record of a report and the caller gets
 * that row back. `gate-closed` means some OTHER report already spent the one.
 */
export type LiveReservation =
  | { status: 'reserved'; report: ReportRecord }
  | { status: 'duplicate'; report: ReportRecord }
  | { status: 'gate-closed' }

/**
 * Claim the one live submission and write its row in a SINGLE statement.
 *
 * This is the fix for #98 and the shape matters more than the code. The gate
 * used to be `countLiveReports() > 0` followed, much later, by an insert that
 * happened only AFTER the city had been posted to. Two requests in flight at
 * once both counted zero and both reached the city, so the safeguard against
 * filing a real ábending by accident failed in exactly the situation it exists
 * for: the one deliberate real send, with somebody watching a screen and able
 * to press twice.
 *
 * A reservation alone does not fix it. Two requests carrying DIFFERENT ids both
 * insert successfully, because the primary key has nothing to say about them.
 * What makes this safe is that the condition and the write are one statement:
 * SQLite evaluates `NOT EXISTS` and performs the insert atomically, so the
 * second request sees the first request's row no matter how the two interleave.
 *
 * Three outcomes, distinguished after the fact because SQLite reports a refused
 * conditional insert as zero changes rather than as an error:
 *
 *   changes > 0            the gate was open and is now ours
 *   changes = 0, id found  a repeat of the report that holds it
 *   changes = 0, no id     a different report already spent it
 *
 * Safe on D1 for a reason worth writing down, since it is the whole fix.
 * Without read replication there is exactly one Durable Object per database, and
 * with it every WRITE is still forwarded to the primary; a plain
 * `env.DB.prepare()` does not use the Sessions API and so never reads a replica
 * at all. So both statements meet the same SQLite writer and the second sees the
 * first's committed row. That much is Cloudflare's documented architecture; that
 * two conditional inserts therefore cannot both succeed is inference from it
 * plus SQLite's statement atomicity, not a sentence in their docs.
 *
 * There is a window, and it is deliberate. Between this and
 * `completeLiveReport` the row reads `sentAt = null` and `accepted = null`, so a
 * same-id repeat or a `GET /api/reports/:id` landing in that window is answered
 * with a row that is true but not yet finished. The old order never exposed a
 * partial row because it never wrote one until it was too late to help.
 *
 * The row is written with `sent_at = null` and `dry_run = 0`, so it counts
 * against the gate from the moment it exists. That means a live attempt whose
 * POST then fails still spends the one, which is deliberate: a fetch that
 * throws cannot tell "never left the isolate" from "arrived and the answer was
 * lost", and only one of those is safe to retry. It is also what the previous
 * code did, by inserting the failure with `dryRun: false`.
 */
export async function reserveLiveReport(db: D1Database, report: NewReport): Promise<LiveReservation> {
  let changes = 0
  try {
    const result = await db
      .prepare(
        `INSERT INTO reports (${COLUMNS})
         SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
         WHERE NOT EXISTS (SELECT 1 FROM reports WHERE dry_run = 0)`,
      )
      .bind(
        report.id,
        report.category,
        report.latitude,
        report.longitude,
        report.description,
        report.email,
        report.photoCount,
        report.photoBytes,
        0, // dry_run: a live reservation, counted by the gate immediately
        report.createdAt,
        null, // sent_at: filled in by completeLiveReport once the city answers
        null, // city_status
        null, // city_reference
        null, // rejection
        null, // outcome
        null, // outcome_at
      )
      .run()
    changes = Number(result.meta?.changes ?? 0)
  } catch (error) {
    // The id is already stored as a row the gate does not count, i.e. a dry-run
    // one, so `NOT EXISTS` let the insert through and the primary key stopped
    // it. Same answer as the check-then-act loser in the dry-run path.
    if (!isDuplicateKey(error)) throw error
    const stored = await getReport(db, report.id)
    if (stored === null) throw error
    return { status: 'duplicate', report: stored }
  }

  if (changes > 0) {
    const stored = await getReport(db, report.id)
    if (stored === null) throw new Error('the live reservation was written and cannot be read back')
    return { status: 'reserved', report: stored }
  }

  const stored = await getReport(db, report.id)
  return stored === null ? { status: 'gate-closed' } : { status: 'duplicate', report: stored }
}

/**
 * Fill in what the city said, on a row `reserveLiveReport` already wrote.
 *
 * Separate from the insert because the row has to exist BEFORE the city is
 * posted to; this is the second half of that split.
 */
export async function completeLiveReport(
  db: D1Database,
  id: string,
  fields: {
    sentAt: string | null
    cityStatus: number | null
    cityReference: string | null
    rejection: Rejection | null
  },
): Promise<ReportRecord> {
  await db
    .prepare('UPDATE reports SET sent_at = ?, city_status = ?, city_reference = ?, rejection = ? WHERE id = ?')
    .bind(fields.sentAt, fields.cityStatus, fields.cityReference, fields.rejection, id)
    .run()
  const stored = await getReport(db, id)
  if (stored === null) throw new Error('the live reservation disappeared between the send and the update')
  return stored
}

