#!/usr/bin/env bash
# Rejects AI attribution before the commit exists.
#
# Widened 2026-08-09. This used to match `Co-Authored-By` only, which meant it
# would have passed the commit a cloud session authored as
# `Claude <noreply@anthropic.com>` even if it had run — the trailer was absent,
# the identity was the marker. It also missed `Claude-Session:` pointers and
# `🤖 Generated with` footers, both of which reached master in PR #187.
#
# This is the local half. It cannot run at all on a machine that never installed
# lefthook, which is how #187 and #188 got through, so the authoritative check is
# .github/workflows/ai-authorship.yml — keep the two in agreement.
set -uo pipefail

MSG=$(cat "$1")
AI='Claude|Anthropic|Copilot|GPT|OpenAI|Gemini'
failed=0

# A marker is a trailer or a footer on its own line, not a mention in prose.
# Defer to git's trailer parser so that a commit message DOCUMENTING this rule
# does not fail it; an unanchored match would make the policy unamendable.
TRAILERS=$(git interpret-trailers --parse "$1" 2>/dev/null || true)

if printf '%s' "$TRAILERS" | grep -qiE "^Co-Authored-By:.*($AI)"; then
    echo "❌ AI Co-Authored-By trailer in the commit message."
    failed=1
fi

if printf '%s' "$TRAILERS" | grep -qiE "^Claude-Session:|^[A-Za-z-]+:[[:space:]]*https://claude\.ai/"; then
    echo "❌ Claude session reference in the commit message."
    failed=1
fi

if printf '%s' "$MSG" | grep -qiE "^[[:space:]]*(🤖[[:space:]]*)?Generated (with|by).*($AI)|^[[:space:]]*🤖"; then
    echo "❌ Generated-with footer in the commit message."
    failed=1
fi

# The identity is a marker in its own right, and the one this hook used to miss.
AUTHOR="$(git var GIT_AUTHOR_IDENT 2>/dev/null || true)"
COMMITTER="$(git var GIT_COMMITTER_IDENT 2>/dev/null || true)"
if printf '%s\n%s' "$AUTHOR" "$COMMITTER" | grep -qiE "$AI|noreply@anthropic\.com"; then
    echo "❌ Commit is attributed to an AI identity, not a human:"
    printf '   author:    %s\n   committer: %s\n' "$AUTHOR" "$COMMITTER"
    failed=1
fi

if [ "$failed" -ne 0 ]; then
    echo "   Commits in this repo list only human authors."
    exit 1
fi
