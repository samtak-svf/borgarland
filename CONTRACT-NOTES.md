# The relay request contract — what changed and why

The Android app and the Worker relay disagreed about the request they
exchange, and the disagreement was invisible because the app had been tested
against a permissive dev-machine mock that accepted anything. This document
records the fix: one machine-readable file, `data/relay-request.json`, that
names the multipart parts the app may send, read by both sides, with a drift
check that makes a re-introduced disagreement a red build. It follows the
shape of `data/reykjavik-form.json` — facts with provenance in one file,
consumers reading it instead of restating them — and the Android build already
had the pattern (`copyFacts` in `android/app/build.gradle.kts` copies a root
file into assets at build time).

## What was wrong

The app sent the city's vocabulary to the relay: `type`, `category` as the
display name (`Ruslafötur`), `summary` as `Ábending -> Ruslafötur`, the
coordinate as `lat`/`lng`, and the photo under the city's own field name
`files`. The relay reads `category` as the slug, `latitude`/`longitude` and
`photo` parts. Every field disagreed. Verified against the real local Worker
before the fix:

| Request | Result |
|---|---|
| The app's exact request: `type`, `category=Ruslafötur`, `summary`, `lat`, `lng`, `description`, `files` (1.1 MB `mynd.jpg`) | `400 {"error":"unknown-category"}` — the display name is not a slug |
| Same, with `category=ruslafotur` (slug) | `400 {"error":"invalid-coordinate"}` — the relay reads `latitude`/`longitude` |
| Same, with `latitude`/`longitude` names | `201` with `photoCount: 0` — the `files` part was silently ignored; a report with no photo accepted |

The third row is the worst failure: silent data loss, no error.

## What `data/relay-request.json` holds

The field keys are the wire names, in the order the app writes them:

- `category` — the category slug, one of `data/reykjavik-form.json`
  `categories[].slug`. The only identifier the app has for a category.
- `latitude` / `longitude` — WGS84 decimal degrees, dot separator.
- `description` — required, `maxLength` restated from the city facts and
  pinned to them by the check.
- `email` — required of the APP, though the relay still accepts a report
  without one and the city treats it as optional (#163, decision 0015).
- `photo` — optional, repeated; `accept` restated from the city facts and
  pinned by the check.

Plus `endpoint` (path, method, content type). The file carries provenance on
every field, like the facts file, and deliberately contains no city display
name, type or summary string — the check asserts that.

## How each side reads it

**Worker** (`worker/src/app.ts`): imports `data/relay-request.json` and uses
it for everything the request boundary needs:

- the set of allowed part names, enforced on the wire — any part the contract
  does not name is rejected `400 {"error":"unknown-field","field":…}`. A stale
  app that still speaks the city's vocabulary fails loudly here instead of
  being ignored field by field;
- the description limit and the accepted photo MIME list (previously exported
  from the city adapter; now they live with the request they validate, and the
  check keeps them equal to the city facts);
- the endpoint path the router answers.

**Android** (`android/app/build.gradle.kts`): `copyRelayRequest` copies the
file into `src/main/assets` at build time, exactly like `copyFacts`; the asset
is gitignored. The app parses it (`data/RelayRequest.kt`) and `RelayClient`
constructs the multipart body by iterating the contract's fields: parts are
written under the contract's own keys, in the contract's order, and a required
field the app has no value for throws before anything is sent. The payload
model (`Report.kt`) now carries `categorySlug`, `latitude`, `longitude`,
`description`, `photos` — no city vocabulary. The city's `type` remains in the
app only as the picker's general/specific label, read from the facts asset,
never sent.

## The drift check

Four layers, all failing on the same drift:

1. **`scripts/check-relay-contract.mjs`** (run standalone and in CI):
   - the field set is exactly the six documented names, in order;
   - `type`, `summary`, `lat`, `lng`, `files` are absent from the field set,
     and no city display name or summary string appears anywhere in the file;
   - the requiredness matrix matches what the relay enforces;
   - `description.maxLength` and `photo.accept` equal the city facts;
   - `worker/src/app.ts` imports the file and `android/app/build.gradle.kts`
     copies it (no second copy to drift);
   - `--require-asset` (CI, after the Gradle build) byte-compares the app's
     asset copy against the root file.
2. **Worker tests** (`worker/tests/contract.test.ts`): the wire enforces the
   contract — each city-vocabulary field name is posted and must come back
   `unknown-field`; the required fields, removed, must be rejected. The shared
   fixture (`reportForm`) builds its multipart by iterating the contract, so a
   renamed field changes the tests rather than silently changing the request.
3. **Android tests** (`RelayRequestTest`): the body `RelayClient` builds
   contains exactly the contract's parts in order, with our vocabulary and
   none of the city's; the contract asset agrees with the facts asset where it
   claims to.
4. **iOS tests** (`ios/BorgarlandCore`, `RelayRequestTest`, run by the
   `ios-core` job): the same assertions against the Swift builder — the parts
   in the contract's order, the exact expected bytes, the city's vocabulary
   absent from the body. Two differences from the Android layer are worth
   knowing. There is no asset copy to byte-compare, because the Swift tests
   read the repository's own `data/` files directly through a path derived from
   `#filePath`, so the second copy `--require-asset` exists to police never
   comes into being. And the ordering is structural rather than checked:
   Kotlin iterates a map whose order the JSON preserves, Swift's `Dictionary`
   has no order at all, so the six roles are a fixed struct with a fixed
   accessor. A decoded map there would have reordered the body on every run.

What the check would catch: someone restating a field name on either side,
re-adding a city field (`type`, `summary`, `lat`, `lng`, `files`), the
description limit or photo MIME list drifting from the city facts, the asset
copy going stale, or the app and relay re-disagreeing on any part name.

## Places the repo did not say, so this change chose

- **`latitude`/`longitude` over `lat`/`lng`.** The relay's domain vocabulary
  (`domain.ts`, the DB schema, the tests) already speaks the full words; `lat`
  and `lng` are the city's own field names for the same values and, per
  AGENTS.md, belong to the adapter alone. Full words won; the app changed.
- **`photo` over `files`.** The relay already read `photo`; `files` is the
  city's field name for the same thing, so writing it was the same defect
  class as `lat`/`lng`. The contract pins `photo`.
- **Where the description limit and photo MIME list live.** They are city
  facts, but they validate the relay's *request*; they now live in the
  contract, and the check pins them to the facts file so the restatement
  cannot drift.
- **Unknown fields are rejected, not ignored.** Multipart parsing ignores
  extra parts by default; the relay now rejects any part the contract does not
  name. This is what turns a stale client into a loud 400 instead of silent
  field-by-field ignoring.
- **The contract carries no category values.** The slug list stays in
  `data/reykjavik-form.json`, which both sides already read; the contract
  references it as the source of `category` values.
- **`type` stays in the app's facts model.** The picker renders the city's
  general/specific distinction as a label (`Almenn ábending` / `Sérstök
  ábending`) from the facts asset; it is never sent. `summary` was dropped
  from the model entirely — nothing uses it anymore.
- ~~**Email is in the contract but never sent.**~~ — no longer true as of
  #163. Both apps now ask for an address, keep it on the device and send it
  with every report; the city's confirmation mail is the only channel the
  reporter has back, and there is no phone field on the city's form to be an
  alternative. `RelayRequestTest` pins the opposite of what it used to: a
  payload without an address cannot be built at all. The relay is deliberately
  NOT tightened to match — see decision 0015 for why that asymmetry is the
  safe direction.

## Re-running the verification

```bash
# 1. Real Worker locally (no deploy, no D1 on Cloudflare; local state only):
cd worker
wrangler d1 execute borgarland-relay --local --file=migrations/0001_init.sql
wrangler d1 execute borgarland-relay --local --file=/tmp/borgarland-seed.sql   # three fixture addresses
wrangler dev --port 8787

# 2. The app's request, before and after the fix:
node scripts/post-relay-request.mjs --old-app    # the pre-fix request: must be 400 unknown-field
node scripts/post-relay-request.mjs              # the app's request today: must be 201, photoCount 1

# 3. The suites and the check:
cd worker && npm run check
cd ../android && ./gradlew testDebugUnitTest
node scripts/check-relay-contract.mjs --require-asset
```

The seed file is the three fixture addresses from
`worker/tests/helpers/fixtures.ts` (`Laugavegur 1`, `Borgartún 12`,
`Hamraborg 3`); the real registry is seeded by `worker/scripts/refresh-registry.mjs`.
Nothing in this flow sends a request to reykjavik.is: the relay is in dry run
by default, and `post-relay-request.mjs` contains no city URL.
