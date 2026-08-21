# The submission payload, field by field

Everything here was read off the live form on 2026-08-21 by driving it in a real
browser and watching the network, then confirmed against the server with
requests that it rejected. Nothing was submitted.

This is the specification `worker/src/adapters/reykjavik.ts` implements, and
`scripts/send-report.mjs` is its executable form.

## The request

```
POST https://reykjavik.is/abendingar/senda-abendingu/<slug>
Content-Type: multipart/form-data
```

No cookie, no CSRF token, no captcha, no `Origin` check, no session of any kind.
The two-step flow in the browser is presentational: step one is a `GET` with
`?cat=<slug>` that `308`-redirects to the same path, and the redirect target is
where the real `POST` goes.

## Fields

| Field | Required | Source | Notes |
|---|---|---|---|
| `type` | yes | fixed per category | `general` for `almenn-abending`, `specific` for the other eleven |
| `category` | yes | fixed per category | Icelandic display name, e.g. `Ruslafötur` |
| `summary` | yes | fixed per category | `Ábending -> <category>`, ASCII arrow |
| `lat` | **see below** | map or address | decimal degrees, WGS84, full precision |
| `lng` | **see below** | map or address | decimal degrees, WGS84, full precision |
| `description` | **yes** | user | max 2500 chars. The only field the server enforces |
| `files` | no | user | repeated part, `image/jpeg`, `image/png`, `image/gif` |
| `email` | no | user | the only way the reporter hears anything back |

There is **no address field in the payload**. The address search exists purely
to move the map marker; what gets submitted is always a coordinate. This is what
makes the whole thing workable for the case that started this project — a litter
bin standing on a path has no address, only the coordinate that came with the
photo.

### Only `description` is enforced

An empty POST returns `400` with:

```json
{"error": "Missing required fields", "inputErrors": {"description": ["Vinsamlegast skrifaðu lýsingu …"]}}
```

`lat` and `lng` are **not** in `inputErrors`. They appear to be enforced in the
browser only, by the map picker refusing to submit without a marker.

Whether a report with a description and no coordinate is actually accepted was
**not tested and must not be** — a request that passes validation creates a real
report in a real work queue.

The consequence is a requirement on our side, not theirs: **the relay must reject
a report with no coordinate**, because the city will not. A bug in the app that
drops the location would otherwise produce a silent stream of reports nobody can
act on.

Note also what the `400` does *not* mean. The string "Hvar er þetta? Sláðu inn
heimilisfang eða veldu staðsetningu á kortinu." appears in that response, but it
is the static help text under the location field, present in every render of the
page. It is not a validation error, and asserting on it proves nothing.

## The twelve categories

| slug | `type` | `category` | `summary` |
|---|---|---|---|
| `almenn-abending` | `general` | `Almenn ábending` | `Ábending -> Almenn ábending` |
| `holur-i-gotu` | `specific` | `Holur í götu` | `Ábending -> Holur í götu` |
| `heimilissorp` | `specific` | `Heimilissorp` | `Ábending -> Heimilissorp` |
| `snjor-og-halka` | `specific` | `Snjór og hálka` | `Ábending -> Snjór og hálka` |
| `numerlausir-bilar` | `specific` | `Númeralausir bílar` | `Ábending -> Númeralausir bílar` |
| `gras-og-grodur` | `specific` | `Gras og gróður` | `Ábending -> Gras og gróður` |
| `ruslafotur` | `specific` | `Ruslafötur` | `Ábending -> Ruslafötur` |
| `gotusopun` | `specific` | `Götusópun` | `Ábending -> Götusópun` |
| `nidurfoll` | `specific` | `Niðurföll` | `Ábending -> Niðurföll` |
| `ljosastaurar` | `specific` | `Ljósastaurar` | `Ábending -> Ljósastaurar` |
| `umferdaroryggi` | `specific` | `Umferðaröryggi` | `Ábending -> Umferðaröryggi` |
| `bilastaedasjodur` | `specific` | `Bílastæðasjóður` | `Ábending -> Bílastæðasjóður` |

`almenn-abending` being `general` rather than `specific` is the only structural
difference; its form is otherwise identical, location field included. Node ids,
the two categories that carry an extra panel, and the English-language variant
are below.

## The category taxonomy

The picker page is a Drupal-backed list; its loader data carries more per
category than the rendered form shows. Read from the hydrated route
`projects/abendingar/routes/categories-3` on 2026-08-21.

| slug | node id | `type` | extra panel |
|---|---|---|---|
| `almenn-abending` | 3217283 | `general` | |
| `holur-i-gotu` | 3217284 | `specific` | |
| `heimilissorp` | 3217288 | `specific` | Sorphirðudagatal, button to `/sorphirdudagatal` |
| `snjor-og-halka` | 3217292 | `specific` | Vetrarþjónusta, text only |
| `numerlausir-bilar` | 3217293 | `specific` | |
| `gras-og-grodur` | 3217294 | `specific` | |
| `ruslafotur` | 3217295 | `specific` | |
| `gotusopun` | 3217296 | `specific` | |
| `nidurfoll` | 3217297 | `specific` | |
| `ljosastaurar` | 3217298 | `specific` | |
| `umferdaroryggi` | 3217299 | `specific` | |
| `bilastaedasjodur` | 3217300 | `specific` | |

This table is what the **city** accepts, and the app carries all twelve. The
scope test — a human walking with a phone — governs the interaction rather than
the taxonomy; see [AGENTS.md](../../AGENTS.md). Keep the distinction when
reading this file regardless: it documents the endpoint, not the product.

**The taxonomy is flat, and nothing diverts you.** Only two categories carry a
`relatedContent` panel, and both are informational: the waste one offers a
collection calendar alongside the form, the snow one explains the gritting
priority order. Neither replaces the form, and no category hands you off to
another system. So an app does not have to reproduce any branching — twelve
chips, one form.

The node ids run 3217283 to 3217300 with six missing (3217285 to 3217287,
3217289 to 3217291). Six sibling nodes were created with these and are no longer
published. Worth knowing only because it means the list is editorial and can
grow back: treat the categories as data to re-check, not as a constant.

## Locale changes what the city receives

There is a parallel English form at `/en/suggestion/send-suggestion/<en-slug>`,
with its own slugs and its own hidden values:

```
POST /en/suggestion/send-suggestion/waste-bins
  category = Waste bins
  summary  = Suggestion -> Waste bins
```

The slugs map one to one — `ruslafotur`/`waste-bins`, `holur-i-gotu`/`potholes`,
`numerlausir-bilar`/`abandoned-cars`, `bilastaedasjodur`/`parking-service`, and
so on — but the locale is not cosmetic: it decides the language of the metadata
that lands in the city's work queue.

**Always post the Icelandic form**, whatever language the app's interface is in.
The people triaging these read Icelandic, and a queue split across two
vocabularies for the same twelve things is a problem we would be creating for
them.

## An unknown slug does not 404

This is the trap. Posting to a slug that does not exist returns **`400`**, the
same status as a validation failure:

| slug | status | body |
|---|---|---|
| `ruslafotur` | 400 | validator envelope, `category` hidden field present |
| `waste-bins` (on the Icelandic path) | 400 | a page titled "Síða fannst ekki (404)" |
| nonsense | 400 | empty |
| *(empty)* | 405 | the picker route is GET-only |

So the status code alone cannot tell "I typo'd the category" from "I forgot the
description", and a client that trusts it will report the wrong thing to the
user and log the wrong cause. The discriminator is the body: a real validation
failure carries `Missing required fields` **and** re-renders the form with the
`category` hidden field filled in.

The practical consequence is that `scripts/send-report.mjs` and the Worker
adapter both hold the category list themselves and reject an unknown slug before
sending. That is not premature caution; it is the only place the mistake is
catchable.

## Supporting endpoints

Both are unauthenticated `GET`s. The browser calls them through React Router's
single-fetch variant (`…​.data?…&_routes=…`), but the plain paths return ordinary
JSON and are what a client should use.

**Address search** — `GET /location/addresses?q=<prefix>`

```json
{"addresses":[{"fasteignarheiti_nefnifall":"Laugavegur 1","postnumer_id":"101"}, …]}
```

**Address to coordinate** — `GET /abendingar/addressInfo?a=<address>&p=<postcode>`

Note the path: it is under `/abendingar/`, not `/location/`, even though its
sibling is not. Both parameters are required; omitting either returns
`{"error":"Invalid input\npostCode: …\naddress: …"}`.

```json
{"addressInfo":[{"street":"Laugavegur","address":"Laugavegur 1","district":"0000",
                 "zip":"101","geometry":{"lat":64.14658919,"lng":-21.93279823}}]}
```

An address the register does not hold returns `{"addressInfo":[]}` rather than an
error — `Borgartún 12` does this, because the building is registered as
`Borgartún 12-14`. Match the string the search endpoint returned, do not
construct it.

**There is no reverse geocoding.** Nothing turns a coordinate back into an
address. That is fine for us — the payload wants the coordinate anyway — but it
means the app cannot label a report with a street name from the city's own data.

## Unknowns

- **Maximum upload size and file count.** The client uses react-dropzone with no
  configured `maxSize`, so the limit is whatever the server enforces, and finding
  it means uploading until something breaks. Not worth a real submission; treat
  it as unknown and downscale aggressively.
- **What a success response looks like**, and whether it carries anything
  resembling a reference number. Determinable only by filing one real report,
  which is a thing to do once, deliberately, at the end of a build.
