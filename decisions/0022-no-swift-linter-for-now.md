# 0022 — No Swift linter for now, and what would change that

- **Date:** 2026-09-15
- **Status:** Accepted

## Context

`data/platform-parity.json` declares `lint-in-ci` as `android-only`, and that
asymmetry is real rather than an oversight: Android runs `ktlint` and Android
lint in `.github/workflows/android-ci.yml`, and iOS runs neither. The parity
check caught the asymmetry the moment ktlint landed, which is the tool doing its
job. What nobody had done was decide what to do about the iOS half (#206).

The iOS half is 45 Swift files and 7,256 lines. Nothing can compile it on this
machine — there is no Mac and no Swift toolchain — so `ios-ci.yml` is the only
compiler, and `swift test` on the host is the only test runner.

## What could be measured without a Mac

A linter has to justify itself by what it catches, so the first question is
whether the code shows the defects a Swift linter exists to find. Counted over
`ios/**/*.swift` on 2026-09-15:

| Signal | Count |
|---|---|
| `try!` | 0 |
| `fatalError` | 0 |
| `as!` | 1 |
| `print(` | 0 |
| `TODO` / `FIXME` | 0 |
| lines with trailing whitespace | 0 |
| lines over 120 columns | 26 |
| lines over 100 columns | 107 |
| **files containing a line over 100 columns** | **22 of 45** |

The first six rows are the class SwiftLint's defaults are built around, and they
are essentially absent: this is not a codebase littered with force unwraps and
stray prints.

The last two rows are what adopting `swift-format` would cost first. Its default
line length is 100, and **half the files carry a line over it**, so the gate
cannot be green until a reformat touches 22 of the 45 files. That is a large
mechanical diff in a repository whose remaining known defects are behavioural and
device-only — #110 (a keyboard covering a submit button), #126 (a session that
left no trace), #139 (a permission asked twice), #196 (a number that belonged to
the suite rather than the test). None of those is the kind of thing a linter
catches. The compiler already runs on every PR, and `swift test` already runs on
the host; between them they gate everything a linter would have gated here.

## Decision

**Neither linter, for now.** `lint-in-ci` stays `android-only`, with its reason
pointing at this record instead of at an issue.

This is a deferral with a stated trigger, not a claim that linting is worthless.
The cost side is measured above; the benefit side has no evidence behind it in
this repository, and buying a gate with a 22-file reformat on spec is the trade
this project's own discipline exists to refuse.

## Consequences

- The asymmetry stays, and it stays **deliberate**: the parity file is the
  record, and a Swift linter appearing on either platform turns CI red until
  someone writes down what the other platform does about it.
- Nothing about the code is now considered clean. It is unmeasured by a linter,
  which is a different statement, and the count table above is the whole of what
  is known.
- The named follow-up if this is ever revisited is **the ratchet**: run the
  linter only over the files a pull request touches. That keeps the existing 45
  files exactly as they are, needs no reformat commit, and stops new violations
  from arriving — which is the part of the benefit that is collectable without
  paying the cost.

## Options that lost

**Add SwiftLint with the defaults.** The first thing anyone reaches for, and it
is the option with the least known about it here: SwiftLint has to be built or
fetched on the runner, and its default rule set is opinionated in ways this
codebase has never been written against, so the first run's violation count is
unknown. Loses to a decision that can be made from measurements rather than from
hoping the first run is small.

**Add `swift-format`.** Ships with the Swift toolchain, so it is the cheaper of
the two to try, and it formats rather than merely complaining. Loses on the
22-of-45 measurement: the tool's first act would be a diff larger than several
real changes, and the project would then own a formatting rule it never chose.

**Decide nothing and leave it as "no decision has been taken".** What the parity
reason said until now, and the reading a new session gets from it is *somebody
should add this*. The question is not a capability gap to close but a trade to
weigh, and "weighed, and not worth it yet, and here is the number that would
change my mind" is a better state than "open".

## What would change this

Either of two things, and both are observations rather than opinions:

1. **A defect appears that a linter would have caught** — a force-unwrap crash in
   a release build is the concrete one, and it would make the case better than
   any style argument.
2. **Someone measures the first run and it is small.** The way to measure it is
   to run `swiftlint` or `swift format lint` over `ios/**` on a Linux runner
   once, in a scratch branch, and read the count. If the diff turns out to be a
   handful of files rather than 22, this decision was made on the wrong number
   and should be revisited immediately.
