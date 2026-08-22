-- The registry's own age, so that staleness can be read instead of guessed.
--
-- Decision 0009 accepted keeping Staðfangaskrá inside the relay and recorded
-- the cost: "the refresh chore is real and unowned ... a stale registry
-- silently degrades the jurisdiction check rather than failing it". The reason
-- it was silent is that nothing anywhere read the snapshot's date. This table
-- is what makes it readable, and GET /api/health is where it surfaces.
--
-- One row, enforced by the primary key check. scripts/refresh-registry.mjs
-- writes it into the seed after the addresses, so the date and the count always
-- describe the rows that were actually applied rather than a hand-kept note.

CREATE TABLE IF NOT EXISTS registry_meta (
  id          INTEGER PRIMARY KEY CHECK (id = 1),
  snapshot_at TEXT NOT NULL,
  row_count   INTEGER NOT NULL,
  source      TEXT NOT NULL
);
