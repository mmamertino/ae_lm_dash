#!/bin/bash
# SessionStart hook: if the project's pinned copier tag is behind the
# template's latest tag, print a one-line reminder. Silent otherwise.
# Fail-silent on every error path — never block session start.

set +e

ANSWERS="$CLAUDE_PROJECT_DIR/.copier-answers.yml"
# Skip when running from the template repo itself (no rendered answers file).
[ -f "$ANSWERS" ] || exit 0
[ -f "$CLAUDE_PROJECT_DIR/.claude/.skip-template-check" ] && exit 0

# Rate-limit: at most one check per project per 24h.
CACHE_DIR="$HOME/.cache/bgi-template-check"
PROJECT_ID=$(printf '%s' "$CLAUDE_PROJECT_DIR" | sha256sum | head -c 16)
TOUCHFILE="$CACHE_DIR/$PROJECT_ID"
if [ -f "$TOUCHFILE" ] && find "$TOUCHFILE" -mtime -1 -print 2>/dev/null | grep -q .; then
  exit 0
fi

LOCAL=$(grep '^_commit:' "$ANSWERS" | awk '{print $2}')
# gh api prints error JSON to stdout on failure, so key off exit status.
REMOTE=$(gh api repos/Burning-Glass-Institute/bgi-econ-template/tags --jq '.[0].name' 2>/dev/null) || REMOTE=""
[ -z "$LOCAL" ] || [ -z "$REMOTE" ] && exit 0

mkdir -p "$CACHE_DIR"
touch "$TOUCHFILE"

if [ "$LOCAL" != "$REMOTE" ]; then
  # Emit systemMessage JSON so the reminder is visible to the user.
  # Plain stdout on SessionStart is injected as context for Claude silently.
  printf '{"systemMessage": "Template update available: you'"'"'re on %s, latest is %s. Run /update-template when ready."}\n' "$LOCAL" "$REMOTE"
fi
exit 0
