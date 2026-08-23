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
 * How many reports have actually been sent to the city.
 *
 * Read before every live send, to enforce decision 0006's "one". Counts rows
 * rather than trusting a flag somewhere, because the database is the only thing
 * that survives a deploy, a new isolate and a re-set secret.
 */
export async function countLiveReports(db: D1Database): Promise<number> {
  const result = await db.prepare('SELECT COUNT(*) AS n FROM reports WHERE dry_run = 0').all()
  return Number((result.results?.[0] as { n?: unknown } | undefined)?.n ?? 0)
}
