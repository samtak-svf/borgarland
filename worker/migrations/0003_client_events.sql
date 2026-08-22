-- What the app noticed while someone filed a report.
--
-- The relay's `reports` table records what was FILED. Everything before that
-- was invisible: whether the camera opened, how long the coordinate took to
-- arrive and how accurate it was, which category was chosen, whether the
-- description was friction, and whether a send failed before it ever reached
-- us. During a field test that is most of what there is to learn, and a send
-- that never happened looked identical to one that failed silently.
--
-- Every column here is a number, a timestamp or a value from a fixed set. The
-- `fields` column holds JSON, but only after worker/src/events.ts has validated
-- it against data/relay-events.json, which names no free-text field anywhere.
-- The reporter's description, coordinate, photo and email cannot reach this
-- table.
--
-- `session` is generated fresh on every app launch and is not derived from any
-- device identifier, so it groups one sitting and cannot follow a person
-- between them.

CREATE TABLE IF NOT EXISTS client_events (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  session     TEXT NOT NULL,
  name        TEXT NOT NULL,
  -- Milliseconds since the session started, never a wall clock: the app's own
  -- clock is not trustworthy and its absolute value is not interesting.
  at_ms       INTEGER NOT NULL,
  platform    TEXT NOT NULL CHECK (platform IN ('ios', 'android')),
  app_version TEXT NOT NULL,
  -- The validated, allowlisted fields for this event name, as JSON.
  fields      TEXT NOT NULL,
  -- When the relay received the batch. This is the only wall clock involved.
  received_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_client_events_session ON client_events(session, at_ms);
CREATE INDEX IF NOT EXISTS idx_client_events_received_at ON client_events(received_at);
