# Verify app changes on the device

> Moved verbatim from the root `AGENTS.md`, where the rule stays as one line under the heading **Before you change app code: the skills outrank your memory**. Read this on the trigger named in the root's "Rule detail" table.

**Then verify on the device.** `android-ux` is the local companion for that half
and defers to Google for everything about the code. Its first rule is the one
this project learned the expensive way: *the screenshot is the instrument, take
it before you theorise.* #110 was in every screenshot already captured while an
agent read accessibility trees and blamed its own taps.

**Build and test run on a remote Mac build host.** Gradle runs there: `cd android && ./gradlew testDebugUnitTest`; see `android/AGENTS.md`.

A hook in the agent tooling says this once per platform per session on the
first touch of `.kt` or `.swift`, including edits made through the shell. If you
are reading this instead, the hook did its job.
