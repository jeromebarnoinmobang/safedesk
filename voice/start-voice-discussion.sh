#!/bin/bash
# start-voice-discussion.sh — mode discussion vocal self-host pour OpenWork.
# Lance (idempotent) : le TTS local pico (:8200) + le brain-shim cerveau=claude
# (:8089) avec ton second-brain et le STT RunPod. Le bouton « Mode discussion »
# d'OpenWork ouvre http://localhost:8089/voice.
#   ./start-voice-discussion.sh          # démarre / redémarre
#   ./start-voice-discussion.sh stop     # arrête les deux
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
LOG=/tmp/safedesk-voice
mkdir -p "$LOG"

stop() { fuser -k 8200/tcp 2>/dev/null; fuser -k 8089/tcp 2>/dev/null; echo "voix arrêtée"; }
[ "${1:-}" = "stop" ] && { stop; exit 0; }

# jeton second-brain : source unique = config Claude Desktop (arg --header de mcp-remote)
SB_TOK=$(python3 -c "
import json
d=json.load(open('$HOME/.config/Claude/claude_desktop_config.json'))
sb=d['mcpServers'].get('second-brain') or d['mcpServers'].get('secondbrain')
a=sb['args']; print(a[a.index('--header')+1].split('Bearer',1)[1].strip())" 2>/dev/null)
RUNPOD_API_KEY=$(grep '^RUNPOD_API_KEY=' "$HOME/.config/safedesk/voice.env" | cut -d= -f2-)

fuser -k 8200/tcp 2>/dev/null; fuser -k 8089/tcp 2>/dev/null; sleep 1

# 1. TTS local (pico2wave) — voix de secours tant que l'endpoint RunPod Kyutai
#    est indisponible ; retire VOICE_TTS_URL + remets RUNPOD_TTS_ENDPOINT_ID pour
#    repasser à Kyutai (voix HQ) quand il refonctionne.
setsid node "$DIR/local-tts.mjs" > "$LOG/local-tts.log" 2>&1 &
sleep 1

# 2. brain-shim : cerveau = CLI claude (abonnement) + second-brain, STT RunPod.
setsid env -u ANTHROPIC_API_KEY -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT \
  RUNPOD_API_KEY="$RUNPOD_API_KEY" \
  RUNPOD_STT_ENDPOINT_ID=x9vixlkk7akx9d \
  SECOND_BRAIN_MCP_URL=https://second-brain.mobang.fr/mcp SECOND_BRAIN_MCP_TOKEN="$SB_TOK" \
  VOICE_BRAIN=claude VOICE_MODEL=sonnet VOICE_EFFORT=medium \
  VOICE_TTS_URL=http://127.0.0.1:8200 \
  CLAUDE_BIN="$HOME/.local/bin/claude" BRAIN_SHIM_PORT=8089 PATH="$HOME/.local/bin:$PATH" \
  node "$DIR/brain-shim.mjs" > "$LOG/brain-shim.log" 2>&1 &

for i in $(seq 1 20); do curl -sf -m 2 http://127.0.0.1:8089/health >/dev/null 2>&1 && break; sleep 1; done
echo "voix prête : http://localhost:8089/voice"
curl -s -m 4 http://127.0.0.1:8089/health
