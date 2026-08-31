-- The metadata a field-test diagnosis needs, recorded on the row it belongs
-- to (#186).
--
-- The relay was handed more than it stored, and the gaps were the ones a
-- diagnosis actually needs: which build filed the report, what the photographs
-- really were, what would have gone to the city, and how far the nearest
-- registered address was. None of this is new data on the wire — it is data
-- the relay already had and threw away. Each column answers a question #186
-- names, and every one is nullable so a row written before this migration
-- reads back with NULL rather than failing (the promote and duplicate-check
-- paths read rows written by older relays).
--
--   app_version     — the app's own version string, parsed from the User-Agent
--                     the app sets to "Borgarland/<version>" since #128.
--                     Deliberately NOT the raw User-Agent: a raw UA would
--                     carry the device model — exactly what #128 replaced —
--                     and the events contract records the version and nothing
--                     else, which is the privacy boundary this column keeps.
--                     Null for any sender that is not the app.
--   photo_mimes     — JSON: [{declared, actual}], one entry per photo. The
--                     declared type is what the client claimed and the only
--                     thing the city ever sees; the sniffed type is what the
--                     bytes actually were (image-format.ts). The accept path
--                     refuses a mismatch today, so the pairs match — the
--                     record exists so the day that guard changes is visible
--                     in the data instead of in a support question (#28).
--   city_payload    — JSON: what would have gone over the wire, photo bytes
--                     summarized to name/mime/size and the email removed.
--                     The email is the one thing the relay keeps nowhere
--                     (0004, #163) — "the most sensitive thing in the
--                     request" — and a stored payload that carried it would
--                     be a second store of the same thing in the same table.
--   jurisdiction_km — how far the nearest registered address was, which is
--                     #31's question. Rounded to two decimals; only the
--                     postal code reached the log before, and only on the
--                     accept path.
ALTER TABLE reports ADD COLUMN app_version TEXT;
ALTER TABLE reports ADD COLUMN photo_mimes TEXT;
ALTER TABLE reports ADD COLUMN city_payload TEXT;
ALTER TABLE reports ADD COLUMN jurisdiction_km REAL;
