-- Initial schema for the Borgarland relay. See schema.sql for the reference
-- with rationale; this is the ordered change D1 applies.

CREATE TABLE IF NOT EXISTS reports (
  id            TEXT PRIMARY KEY,
  category_slug TEXT NOT NULL,
  latitude      REAL NOT NULL,
  longitude     REAL NOT NULL,
  description   TEXT NOT NULL,
  email         TEXT,
  photo_count   INTEGER NOT NULL DEFAULT 0,
  photo_bytes   INTEGER NOT NULL DEFAULT 0,
  dry_run       INTEGER NOT NULL DEFAULT 1 CHECK (dry_run IN (0, 1)),
  created_at    TEXT NOT NULL,
  sent_at       TEXT,
  city_status   INTEGER,
  city_reference TEXT,
  rejection     TEXT CHECK (rejection IN ('validation', 'route', 'error')),
  outcome       TEXT CHECK (outcome IN ('fixed', 'not-fixed')),
  outcome_at    TEXT
);

CREATE INDEX IF NOT EXISTS idx_reports_created_at ON reports(created_at);

CREATE TABLE IF NOT EXISTS addresses (
  svfnr        INTEGER NOT NULL,
  street_nf    TEXT NOT NULL,
  house_number INTEGER,
  house_letter TEXT,
  postal_code  TEXT NOT NULL,
  lat          REAL NOT NULL,
  lng          REAL NOT NULL
);
