#!/usr/bin/env bash
# Tests check-msg.sh's subject-prefix rule. Run: bash .lefthook/commit-msg/check-msg.test.sh
set -uo pipefail
HOOK="$(cd "$(dirname "$0")" && pwd)/check-msg.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=Human GIT_AUTHOR_EMAIL=h@example.org GIT_COMMITTER_NAME=Human GIT_COMMITTER_EMAIL=h@example.org
bad=0
run() { # expected-exit subject
  printf '%s\n' "$2" > "$TMP/msg"
  bash "$HOOK" "$TMP/msg" >/dev/null 2>&1; got=$?
  if [ "$got" -ne "$1" ]; then echo "FAIL (want $1, got $got): $2"; bad=1; fi
}
run 1 "fix stuff"
run 1 "Update things"
run 1 "fix: "
run 1 "feature(worker): wrong prefix"
for p in feat fix docs ci chore refactor test perf build style revert workflow ops; do
  run 0 "$p: a descriptive sentence"
  run 0 "$p(scope)!: a descriptive sentence"
done
run 0 "Merge pull request #1 from x/y"
run 0 "fixup! fix: a thing"
[ "$bad" -eq 0 ] && echo "check-msg: all cases pass"
exit "$bad"
