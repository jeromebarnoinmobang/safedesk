#!/bin/bash
# Voice container copy of Jérôme's UserPromptSubmit hook: injects the second-brain
# working-memory snapshot (/session-context) into the voice Claude at every prompt.
# Reads MCP_TOKEN + SECOND_BRAIN_URL from the environment (set via the container
# env_file) — the file-source below is optional. Silent-fail: never blocks a turn.
[ -n "${MOBANG_FLEET:-}" ] && exit 0
set -u

if [ -f "$HOME/.claude/.env" ]; then
  # shellcheck disable=SC1091
  source "$HOME/.claude/.env"
fi

if [ -z "${MCP_TOKEN:-}" ] || [ -z "${SECOND_BRAIN_URL:-}" ]; then
  exit 0
fi

RESPONSE=$(curl -s --max-time 5 \
  -H "Authorization: Bearer $MCP_TOKEN" \
  "$SECOND_BRAIN_URL/session-context" 2>/dev/null)

if [ -z "$RESPONSE" ]; then
  exit 0
fi

case "$RESPONSE" in
  Unauthorized*|"Internal error"*) exit 0 ;;
esac

echo "$RESPONSE"
exit 0
