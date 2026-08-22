# 0009 — The registry stays in the relay, not behind greenfield's service

- **Date:** 2026-08-22
- **Status:** Accepted

## Context

The relay bundles `iceaddr-ts` and holds Staðfangaskrá in its own D1: 139,347
rows, generated into an 8.8 MB seed by `worker/scripts/refresh-registry.mjs`.
It uses that for two things — reverse-looking a coordinate to its nearest
registered address for the description we send, and reading `SVFNR` for the
jurisdiction check ([0005](0005-addresses-from-the-registry.md)).

`xj-greenfield` already serves a registry service API over a token-gated HTTP
boundary, and `samtak-vefur` consumes it: address search and validate, plus
Þjóðskrá on a second scope, with the token read in exactly one module and a CI
grep enforcing that seam. The registry lives in greenfield's Postgres, refreshed
weekly by cron with an ETag early-exit and an R2 archive, and `samtak-vefur`'s
own founding decision says its D1 never hosts those registries.

The obvious question follows: should Borgarland do the same and delete its copy?
The seam exists, it is mature, and reusing it rather than carrying a second
registry is exactly the instinct this project wants to have.

The service cannot answer our question today. `search` takes text and `validate`
takes a `hnitnum` or a street and postcode; neither takes a coordinate, and
`AddressResult` stops at a `municipality` name without the `svfnr` code the
jurisdiction rule is written against. So the comparison is not "use what exists"
but "build a new endpoint there, then delete ours here".

## Considered options

### A. Keep `iceaddr-ts` and the registry inside the relay
- ➕ The jurisdiction check is a local D1 read inside the same Worker, on the
  critical path of every submission, with no other party involved.
- ➕ Nothing to credential, nothing to rotate.
- ➖ We carry a second copy of a registry that greenfield already keeps fresh.
- ➖ A refresh chore: 38 MB from HMS, regenerate the 8.8 MB seed, load it into
  D1. No cron is wired, so it is manual whenever it starts mattering.

### B. Call greenfield's registry service
- ➕ One registry, kept current in one place by a cron that already runs.
- ➕ Deletes `registry.ts`, `registry-loader.ts`, `jurisdiction.ts`,
  `refresh-registry.mjs`, the addresses table and its migration, the seed, the
  `iceaddr-ts` dependency and two test files.
- ➕ `registry:thjodskra` comes with the same token if we ever need it.
- ➖ Needs a new endpoint in greenfield first: a nearest-by-coordinate query and
  `svfnr` on the result. Roughly 65 lines there and a client seam of about 60
  here, plus two secrets and a service token on a 365-day rotation.
- ➖ **The jurisdiction check becomes an HTTP call to another organisation's
  service, on the critical path of the product's core action.**

## Decision

**Option A.** The registry stays in the relay.

On the question as asked — does this save work and resources — the numbers say
no. B saves a few KiB of gzipped bundle, about 10 MB of D1 that is free anyway,
and a refresh chore that has not started, because the relay is not deployed:
`wrangler.jsonc` still carries a placeholder `database_id` and no cron triggers.
Against that it costs about 125 lines across two repositories and a credential
with an annual rotation duty.

The decisive cost is not code. `samtak-vefur` proves the seam works across
organisations, but there it backs **form autocomplete**, where an outage
degrades a suggestion. Here it would gate **the product's core action**. The
jurisdiction check is what stops a report reaching a city that cannot act on it,
so when the service does not answer the relay must fail closed and refuse. That
turns a greenfield outage, a token rotation mistake or a rate-limit 429 into
"nobody can report anything", on someone else's deploy.

Borgarland is Samtak svf. and `xj-greenfield` is Sósíalistaflokkurinn. The
precedent for crossing that line exists, but the thing being made dependent
here is larger than the thing the precedent covers.

## Consequences

- `iceaddr-ts` stays a dependency of the relay, taken from the published npm
  package rather than a local checkout.
- The refresh chore is real and unowned. Before the relay is deployed, decide
  whether it becomes a cron in `wrangler.jsonc` or a documented manual step;
  the upstream updates at least daily and a stale registry silently degrades
  the jurisdiction check rather than failing it.
- If Borgarland ever needs Þjóðskrá, this decision does not apply to that
  question and should be reopened rather than assumed.

## What would change this

A reverse-geocoding endpoint arriving in greenfield's registry service for its
own reasons, so that adopting it costs only the client seam. At that point B is
roughly 60 lines against a duplicate registry, and the failure-mode argument is
the only thing left to weigh.

## Notes on the measurements

Taken 2026-08-22 by reading both repositories. Two things were deliberately not
estimated: the exact share of the 69.33 KiB bundle that `iceaddr-ts` occupies,
and the added latency of the network hop, which cannot be measured without
calling the service. The service's base URL is an environment binding and
appears in no committed file, so the host itself was not verified from source.
