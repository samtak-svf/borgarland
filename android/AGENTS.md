# Android app context

> Path-scoped context, loaded when you read or edit a file under this directory.
> Read this directly before Android work that opens no file here. Root rules in [AGENTS.md](../AGENTS.md) still apply.

**Gradle runs on a remote Mac build host, not locally.** The command is
`cd android && ./gradlew testDebugUnitTest`, run from the repo root on that host.
The commands in `android/POC-NOTES.md` § Build are what runs there.

**Android — Google's skills decide.** They publish 21 official ones
([github.com/android/skills](https://github.com/android/skills), Apache-2.0),
installed here as the `android-skills` plugin: edge-to-edge and IME insets,
adaptive layout, theming, Navigation 3, CameraX, R8, testing setup, Play. On
anything they cover, read the `SKILL.md` before writing the code rather than
after. This is not deference for its own sake. #110 was fixed by
`Modifier.imePadding()` placed **before** `verticalScroll()`, and a hand-written
note in this machine's own skills directory had the order backwards — appending
the modifier the obvious way would have shipped a quieter second bug on top of
the one being fixed. Three corrections in one line, from the people who own the
framework.
