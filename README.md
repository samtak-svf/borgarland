# Borgarland

Open the phone, point it at the problem, send. That is the whole app.

Reykjavík already takes citizen reports (ábendingar) — an overflowing litter
bin, a hole in the pavement, a dead street light — through a web form at
[reykjavik.is/abendingar](https://reykjavik.is/abendingar/senda-abendingu). The
form works. But nobody out on a walk in the city's public realm (borgarlandið)
is going to stop and fill it in on a phone, so the report never gets made and
the city never learns about the problem.

This is a native Android and iOS app that reduces the whole thing to: camera,
location, send.

Free software, no charge, no ads, no data resale. Built by
[Samtak svf.](https://samtak.is), a cooperative (samvinnufélag).

## Status

**Research complete, nothing built yet.** The feasibility question is answered
in [docs/research/reykjavik-reporting-api.md](docs/research/reykjavik-reporting-api.md).

The short version: Reykjavík publishes no API, and no Icelandic municipality
implements Open311 — but the city's own form endpoint accepts an anonymous
`multipart/form-data` POST from any client, validated server-side, with no CSRF
token and no captcha. That is enough to build on. It is also a dependency we do
not own, which is what shapes the architecture below.

## Shape

```
Android (Kotlin/Compose)  ─┐
                           ├─→  Worker relay (Cloudflare)  ─→  reykjavik.is
iOS (Swift/SwiftUI)       ─┘         │
                                     └─→  D1: our record of what was sent, when
```

Four decisions worth stating early.

**The location is the photo's, not an address.** The city's form leads with
"type in an address". For a litter bin standing on a path that is the wrong
primitive — it has no address, only the coordinate that came with the photo. So
EXIF GPS first, the device fix as fallback, a map only for correcting it, and
address lookup used solely to fill the city's own fields afterwards.

**A relay, not a direct post.** The app could POST to the city from the device
and skip a backend entirely. It should not. The endpoint is undocumented and can
change without notice; if the apps talk to it directly, every change costs an
App Store review before anyone can file a report again. Behind a relay it costs
a deploy. A scheduled contract test watches the endpoint so we hear about a
change from a red build rather than from a user.

**We keep our own record, because nobody else does.** The city exposes no ticket
id, no status and no public register, and publishes no response-time data at
all — its open-data portal has 595 datasets and not one concerns ábendingar. So
the second half of this project falls out of the first: an app that timestamps
its own submissions and later asks the reporter whether the thing actually got
fixed is the only instrument anyone has for measuring the city's follow-through.
That measurement is worth as much as the convenience.

**A graceful fallback.** When the relay cannot reach the city, the app opens the
city's own form pre-filled in a web view rather than failing. A report that takes
thirty seconds beats a report that never happens.

## Scope, first release

Reykjavík only. The capital area does not share one reporting system —
Mosfellsbær runs MainManager behind ASP.NET `__VIEWSTATE`, Hafnarfjörður a
Drupal module — so each additional municipality is real work, not a config
entry. Get one right first.

## Contributing

`lefthook install` after cloning. Feature branch and a PR; `main` is protected.
Conventions are in [AGENTS.md](AGENTS.md) — including the one about never filing
a real report as an automated test.

## License

MIT. See [LICENSE](LICENSE).
