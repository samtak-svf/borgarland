# How Reykjavík's citizen reporting system actually works

Findings from a black-box investigation on 2026-08-21. Everything below was
established from public HTTP responses only; nothing was submitted to the city
beyond one deliberately empty request that the server rejected with `400`.

## Summary

Reykjavík publishes **no official API** for citizen reports (ábendingar), and
Iceland has **no Open311 implementation** in any municipality. But the web form
at `reykjavik.is/abendingar/senda-abendingu` posts to an endpoint that accepts a
plain `multipart/form-data` request from any client: no session cookie, no CSRF
token, no captcha, no `Origin` check. For our purposes that endpoint *is* the
API — an undocumented one we do not control.

## The submission endpoint

The public form is a two-step React Router (Remix) flow.

**Step 1** — category picker, a `GET` to `/abendingar/senda-abendingu?cat=<slug>`
which `308`-redirects to `/abendingar/senda-abendingu/<slug>`.

**Step 2** — the real form:

```
POST https://reykjavik.is/abendingar/senda-abendingu/<category-slug>
Content-Type: multipart/form-data
```

| Field | Type | Notes |
|---|---|---|
| `type` | hidden | `specific` |
| `category` | hidden | display name, e.g. `Ruslafötur` |
| `summary` | hidden | e.g. `Ábending -> Ruslafötur` |
| `lat` | hidden | filled by the map / address picker |
| `lng` | hidden | same |
| `description` | textarea | **required**, max 2500 chars |
| `files` | file, multiple | `image/jpeg`, `image/png`, `image/gif` |
| `email` | text | optional; the only way to get follow-up |

Every field's exact value per category, the address endpoints and what is
still unknown are in [payload-map.md](payload-map.md). The twelve category
slugs, straight out of the page: `almenn-abending`,
`holur-i-gotu`, `heimilissorp`, `snjor-og-halka`, `numerlausir-bilar`,
`gras-og-grodur`, `ruslafotur`, `gotusopun`, `nidurfoll`, `ljosastaurar`,
`umferdaroryggi`, `bilastaedasjodur`.

### Verified reachable without a browser

```
$ curl -sS -X POST -F "dummy=1" \
    https://reykjavik.is/abendingar/senda-abendingu/ruslafotur
HTTP/2 400
… "error": "Missing required fields",
  "inputErrors": { "description": ["Vinsamlegast skrifaðu lýsingu svo við getum …"] }
```

A `400` carrying the validator's own error envelope proves the route is handled
server-side and reachable anonymously, and that a malformed request creates
nothing.

Note what is *not* in `inputErrors`: `lat` and `lng`. **The only field the city
enforces is `description`** — the location appears to be required in the browser
only, by the map picker refusing to submit without a marker. That was not tested
further, because a request that passes validation files a real report.

The consequence is a requirement on our side rather than theirs: the relay must
reject a report with no coordinate, since the city will not.

### Supporting endpoints, also open

- `GET /location/addresses?q=Laugavegur+1` → JSON list of
  `{fasteignarheiti_nefnifall, postnumer_id}`. Address autocomplete, no auth.
- `GET /location/addressInfo` → address ⇄ coordinates. Parameter names not yet
  determined; the wrong ones return `{"error":"Invalid input"}`.
- Basemap tiles: `borgarvefsja.reykjavik.is/arcgis/rest/services/Kort/Lettkort/MapServer/tile/{z}/{y}/{x}`,
  with `server.arcgisonline.com` World_Light_Gray as fallback. The city's own
  site uses Leaflet against these.

## What the city does *not* give us

- **No status, no ticket id.** The response to a successful submission is a
  thank-you page. If you supply an email you get notifications by mail; there is
  no machine-readable handle for the report afterwards.
- **No public register of open reports.** So the app cannot show "already
  reported" for a location, and cannot de-duplicate against the city's queue.
- **No response-time data.** Reykjavík's open-data portal (Gagnagátt, a CKAN
  instance at `gagnagatt.reykjavik.is`, 595 datasets) contains **nothing** on
  ábendingar: no volumes, no categories, no resolution times. The nearest
  dataset, `rusl-i-rvk`, is annual household-waste tonnage.

That last point matters for the follow-up-quality question. There is no dataset
to audit. The two ways to get the numbers are an information request
(upplýsingabeiðni) under the Information Act (upplýsingalög), or measuring them
ourselves — which is exactly what an app that timestamps its own submissions and
asks the reporter "was this fixed?" would produce. **The app is the measurement
instrument.** That is arguably the more interesting half of the project.

## Other municipalities

The capital area does not share one system, so "one app, every municipality" is
not a small increment.

| Municipality | System | Integration outlook |
|---|---|---|
| Reykjavík | Custom React Router form on `reykjavik.is` | **Easy.** Clean multipart POST, described above. |
| Mosfellsbær | **MainManager** (`mosfm.mainmanager.is/mmv2/MMExternal.aspx`) | **Hard.** ASP.NET WebForms with `__VIEWSTATE`; Leaflet + Dropzone on top. Hostile to third-party clients. |
| Hafnarfjörður | Drupal, `abendingar.hafnarfjordur.is`, `node-indications-add-indication-form` | Untested; a Drupal form means a form-build token, so probably needs a session round-trip. |
| Kópavogur, Garðabær, Seltjarnarnes | Not located at guessed paths | Unknown. |

Reykjavík's own ArcGIS server carries a `MainManager` folder, so the city runs
MainManager for facilities management even though the citizen-facing form is
custom. The vendor has an API; going through MainManager directly would be the
route to covering several municipalities at once, but it needs a commercial
conversation, not reverse engineering.

## Risks worth naming up front

1. **The endpoint is undocumented and unowned.** Reykjavík can change field
   names, add a captcha, or start checking `Origin` at any time, with no notice
   and no obligation to us. Design the client so the submission adapter is one
   swappable module, and keep a fallback that opens the city's own form
   pre-filled in a web view.
2. **Volume without a conversation is a bad opening move.** Building against the
   form is fine for a proof of concept. Before any real user base, the city's
   service and innovation department should be told what we are doing and asked
   for a supported interface. "We built the thing your residents wanted and here
   are the numbers" is a much stronger approach than being discovered.
3. **Personal data.** The app would relay a photo, a location and optionally an
   email to the city. Photos of the public realm routinely catch faces and
   number plates. We need a privacy policy (persónuverndarstefna), a decision on
   whether we retain anything ourselves, and — if we do retain reports in order
   to measure follow-up — a lawful basis for it.
4. **A security finding, not to be tested.** The ArcGIS service
   `Hreinsun/Hreinsun_dev` on `borgarvefsja.reykjavik.is` advertises
   `"capabilities": "Query,Update,Uploads,Editing"` on an anonymously readable
   REST endpoint. Whether writes are actually permitted was **not** tested and
   must not be. If it is genuinely open, it is the city's problem to fix and
   ours to report responsibly to them.

## Prior art

No Icelandic app does this. Internationally the pattern is well established —
FixMyStreet (UK, open source, mySociety) and SeeClickFix (US) both run on
Open311 — so the product shape is proven; the missing piece here is purely the
Icelandic backend.
