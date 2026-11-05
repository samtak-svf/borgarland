# Label sightings and the claim-correction history

> Moved verbatim from the root `AGENTS.md` (agent-config#1482 step 4), where the rule stays as one line under the heading **What belongs in the app: a human walking with a phone**. Read this on the trigger named in the root's "Rule detail" table. It continues [app-scope.md](app-scope.md): "that file" in its first line is `data/category-labels.json`.

Both pickers read that file, so the check is one grep of it rather than a
memory of a screen. Worth saying because the obvious check is worse. iOS build 4
was cut before the labels file was read at all; build 5, uploaded 2026-08-24 and
VALID in TestFlight, is the first iOS build that reads it. **Build 5 has now
been run**, and by more people than the relay can see. App Store Connect records
**three** internal testers on build 5 as of 2026-08-24, with fourteen sessions
between them; the relay recorded **one** walk, at 11:58, accepted and written up
as [`2026-08-24-ios-build-5-first-run`](../../data/field-tests.json). This sentence
said "once" until the tester list was actually read, which is the same mistake as
every other one on this page: a count taken from the record nearest to hand
rather than from the thing being counted. That one walk chose `heimilissorp`, so
it did not settle the label either. Which tester made it is not knowable — App
Store Connect names who installed, the telemetry names no device, and nothing
joins the two.

**The gap between fourteen and one now has a mechanism rather than a suspicion,
and it is not the one #126 thought most likely.** The telemetry buffer is memory
only, and a session where somebody opens the app, looks and leaves reaches no
other flush point: no report, so no send-result flush, and nowhere near the
twenty events the threshold wants. Everything rests on the flush at
`scenePhase == .background` — which posted with `URLSession.shared` from a
process iOS was already suspending, with no background-task assertion asking it
to wait. So the session simply left no trace. #126 guessed that `app-opened`
alone never triggers a flush; it does, and the flush was being killed instead.

Read every iOS count in this file as a **lower bound through build 6**. Build 7
holds an assertion across that flush, which fixes the next walk and recovers
none of the earlier ones.

**The label has now been seen on iOS, on build 6, at 22:00 on 2026-08-24.** A
tester's screenshot of the picker shows `Annað í almannarými` above `Bekkur,
girðing, tré eða annað sem á ekki heima í hinum flokkunum`, read off her iPhone
and matched to `data/category-labels.json` — the same standard the Android half
below is held to. Recorded as
[`2026-08-24-ios-build-6-the-asked-to-answered-gap-measured`](../../data/field-tests.json).
**Seen is not chosen**: she picked `heimilissorp` and switched to `gotusopun`, so
no walk on either platform has yet filed a report under this category from iOS.
Keep the two claims apart, because this page has confused them before.

**On Android somebody has now seen it.** The picker rendered
`Annað í almannarými` with its help line on an SM-S918B on 2026-08-24, read off
the device and matched to the file byte for byte, and the category was then
walked by hand to a report row — recorded as
[`2026-08-24-android-ime-fix-and-the-label-on-a-screen`](../../data/field-tests.json).
The 2026-08-23 run that #101 was filed about is in the same file, and that entry
is careful about what it cannot say: the telemetry carries no device identifier,
so which phone it was is a memory rather than a measurement. True of the event
BODY, which is what that entry meant and what `data/relay-events.json` enforces.
It was false of the transport until 2026-08-24: Android's default `User-Agent`
named the handset model on every request, and three models were visible in the
relay's logs before #128 replaced it with `Borgarland/<version>`. The allowlist
governs what the app sends, never what the platform adds underneath it.

**A build existing and a build having been walked are different claims.** This
paragraph has now been wrong five times, and the fifth failed differently from
the other four: "nobody has installed build 5" was *true when it was written*
and stopped being true at 11:58 the same day, while the sentence sat here for
hours saying otherwise — and in two issue bodies as well, which is where most of
the cost was. A sentence that reports the current state of the world has a shelf
life, and this file is not a place to store one without saying when it was
measured.

The other four were wrong on the day they were written. The third was a
correction that cited `data/field-tests.json` for an observation the file did
not contain; the fourth was this one still saying the run was recorded nowhere
**one commit after the same session recorded it** (#113). Both directions of the
same mistake, and the second was made by the person who had just written the
first correction.

So the check is not "grep before you claim". It is **grep again after you change
the record**, because the thing that most often falsifies a sentence here is
your own last commit.

**And grep for the CLAIM, not for the sentence you remember writing.** The
correction above announced three carriers. There were five. `README.md` said the
build "has not yet been installed by anyone" and `ReportQueue.swift` said it "is
installed nowhere" — the same assertion twice, in the public front door and in a
comment whose reasoning depended on it, and a search for `nobody has installed`
matches neither. The commit that found two carriers by widening a pattern then
stated a count from the pattern it had just been burned by. A prose claim has as
many spellings as the people who wrote it, so search for the several ways it
could be said, or state no number at all — which is what the paragraph two above
already tells you to do.

**A fresh instance, 2026-08-24, and it is the carrier lesson rather than a sixth
wrong claim in this paragraph — the count above is deliberately left alone.**
#127 corrected "build 5 was run once" to three testers and fourteen sessions,
here. `README.md` went on saying "once" for eight hours afterwards, in the public
front door, until a close-out sweep grepped for the claim rather than the file.
The correction found the document it was already reading and stopped there. That
is the whole failure above, repeated by a session that had just written the rule
down — which is the strongest argument this page can make for the seven-step
check in **When new test data arrives** (`data/AGENTS.md`), and why step 6 of it is a gate rather
than a habit.

This paragraph twice said the opposite of the truth, in opposite directions. It
first claimed the rewording existed when it did not; the correction then claimed
it did not exist, and stayed after it was built. Both times the sentence
described an intention rather than the tree. The check is one grep of
`data/category-labels.json`, which is why the file exists.
