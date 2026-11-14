# Field-test data context

> Path-scoped context, loaded when you read or edit a file under this directory.
> Read this directly when a new walk arrives, before touching data/field-tests.json or private/. Root rules in [AGENTS.md](../AGENTS.md) still apply.

## When new test data arrives

A walk produces two records that can falsify each other: the telemetry, which
the phone wrote and nobody can edit, and the screenshots, which show what the
person actually saw. Reading either alone is how a session ends up describing a
walk that did not happen. Do all of this before writing anything down.

**1. Ask the data which build it was, never the tester.** `app_version` in
`client_events` reads `0.1.0 (6)`. A fix that is merged, deployed and installed
is still untested if the walk came from the build before it, and that is the
single most likely way to record a false confirmation.

**2. Get the images onto disk before they scroll away.** They arrive in a chat
thread and are not durable there. Dedupe by SHA-256 against
`private/screenshots` — an end-to-end walk usually re-sends earlier shots, and
four of seven were already held the first time this was done.

**On Android a test-mode walk now photographs itself (#164), which is the half
of this step that used to depend on somebody remembering.** The app writes one
numbered image per step into `files/walk-captures/<session id>/` — photo
captured, location resolved, category chosen, screen left, relay answered — in a
debug build only, from its own window, with no permission and no screenshot
button pressed. Pull them with

```
adb exec-out run-as is.borgarland cat files/walk-captures/<session>/<n>-<step>.jpg \
  > private/screenshots/<date>-walk-<n>-<step>.jpg
```

and index every one of them, because an unindexed image is worse than a missing
one: it looks like evidence and says nothing. The directory is named after the
telemetry session, so the images and the events join without hand-transcription;
that numbering also makes a *missing* image visible, which is how the first walk
showed that its very first event had no window to copy yet. **iOS does not have
this**, and #225 is why: decision 0019 lets one platform lead.

**3. Cross-check the two records against each other, and say which pairs you
checked.** The photo's byte count on the summary screen against
`photo-captured`, the description's character count against
`description-length`, the location label against `location-resolved.source`. If
a pair disagrees, that is the finding — stop and chase it rather than writing
the version that reads better.

**4. Write the field-test entry** in `data/field-tests.json`, keeping the
timeline and the report row as transcription and everything else as
interpretation. `scripts/check-field-tests.mjs` will refuse an event the
allowlist does not name, and refuse a finding with no issue number.

**5. Say what the walk does NOT establish.** This is the step that gets skipped,
and it is the one that stops the next session from inheriting a confirmation
nobody earned. Build 6's first walk measured the asked-to-answered gap and did
**not** test #139, because #139 was about the second report and she took one
photograph. Unobserved is not disproved; write which one it is.

The second walk that evening is the harder version of the same lesson, because
it **looks** like the missing test. Two `photo-captured` and two
`location-permission-asked` in one session id is exactly the shape #139 asked
for, and it still settles nothing: the two are 98 minutes apart with the app
left in between, and the tester's own voice note says she taps `Leyfa einu sinni`
(Allow Once), which returns the permission to `.notDetermined` on its own. A
matching shape is not a matching condition. Read the gaps between the events, not
only the events.

**6. Index every screenshot** in `private/testers.json`, saying what is ON the
screen and what it cross-checks. Run `node scripts/check-private-index.mjs`,
which reconciles the directory against the index and rejects a description too
short to be one. That gate exists because on 2026-08-24 the images were saved,
the entry was written and merged, and nothing indexed them — five against eight,
caught by a person asking. It cannot run in CI and must not: the data is real
names and real addresses, and this repository is public.

**7. Update the tester's roster entry** with state read from the API rather than
from a screenshot, and log the contact with a date.
