# voice/ — parler à voix haute avec l'assistant SafeDesk

Tu parles → **Whisper (GPU serverless RunPod)** transcrit → le **cerveau**
répond en streaming → **Kyutai TTS 1.6B (GPU serverless)** lit la réponse en
français. La page micro (VAD maison, auto-stop au silence) marche sur Chrome,
Android et iOS Safari — aucune Web Speech API.

C'est la brique « LLM gardien vocal » de SafeDesk : un assistant à qui l'on
parle, qui explique sans jargon et met en garde contre les arnaques.
Code hérité du voice-brain de la fleet mobang (v2, prouvé e2e le 2026-07-10).

## Trois cerveaux au choix (`VOICE_BRAIN`)

| | `claude` (défaut) | `openai` | `relay` |
|---|---|---|---|
| Quoi | CLI officiel `claude` (session chaude, streaming) | Tout endpoint OpenAI-compatible — cas nominal : **RunPod serverless vLLM** | Un **agent externe** répond (session Claude Code, Cowork, autre LLM) |
| Capacités | **Agentique** : vrais outils, MCP optionnel | Conversation pure (pas d'outils) | Celles de l'agent connecté |
| Contexte | Gardé par la session chaude | Historique glissant géré par le shim (`VOICE_HISTORY_TURNS`) | Celui de l'agent |
| Coût | Abonnement Max (zéro clé API) | GPU serverless scale-to-zero (centimes) | Celui de l'agent |
| Config | `CLAUDE_CODE_OAUTH_TOKEN` (`claude setup-token`) | `RUNPOD_LLM_ENDPOINT_ID` + `BRAIN_OPENAI_MODEL` (ou `BRAIN_OPENAI_BASE_URL` explicite) | `VOICE_RELAY_URL` + `VOICE_RELAY_TOKEN` (hub second-brain) — ou rien : fichiers locaux + `mcp-voice.mjs` |

### Mode `relay` distant : le hub vocal du second-brain

Le shim POUSSE chaque phrase transcrite au hub (`POST /voice/ask`) puis
long-poll la réponse (`GET /voice/answer/<id>`, annulation par `POST
/voice/cancel/<id>` au timeout). Côté agent, le serveur MCP du second-brain
expose `voice_wait` / `voice_answer` / `voice_status` : **n'importe quelle
session connectée au second-brain peut être le cerveau**, d'où qu'elle tourne.
Aucune entrée réseau vers le bureau n'est nécessaire (un SafeDesk derrière une
box marche pareil qu'un SafeDesk VPS). Les tours livrés à un agent sont
« réclamés » (pas de double exécution si deux sessions écoutent) et portent un
cadrage « transcription non authentifiée » anti-injection.

## Activer

Le shim tourne DANS le conteneur du bureau (service s6 `safedesk-voice`,
supervisé, relancé automatiquement). Il démarre dès que sa config existe :

```bash
cp voice/.env.example /config/.config/safedesk/voice.env   # puis remplir
```

Le home (`/config`) persiste : **une recréation du conteneur garde la voix**
sans rien refaire. La page vit sur `https://<ton-bureau>/voice/` — même auth
que le bureau (nginx proxifie vers le shim local :8088).
`BRAIN_SHIM_TOKEN` (recommandé) : la page l'envoie en `X-Voice-Token`, URL clé
en main `/voice/#t=<token>` ; la tuile « Assistant vocal » de l'app téléphone
le reçoit cuite dans le QR (champ `voice`).

## Les morceaux

| Fichier | Rôle |
|---|---|
| `brain-shim.mjs` | Le serveur : page `/voice/`, `/voice/chat` (+ façade OpenAI `/v1/chat/completions`), `/voice/stt` (blob micro → faster-whisper RunPod), `/voice/tts` (texte → Kyutai RunPod, fallback pocket-tts local), `/voice/warm` (préchauffage STT+TTS+LLM), `/health`. |
| `Dockerfile` | Image cerveau autonome (node:22 + CLI claude) — pour un déploiement hors bureau. |
| `../files/custom-services.d/safedesk-voice` | Service s6 du conteneur bureau — actif si `/config/.config/safedesk/voice.env` existe. |
| `claude-config/` | Settings + hook du cerveau claude (contexte second-brain optionnel). |
| `tts/` | Image du fallback voix local (Kyutai pocket-tts, CPU, français). |

## Tester

```bash
# santé (type de cerveau, backends audio) :
curl -s http://127.0.0.1:8088/health
# cerveau (streame du texte) :
curl -N http://127.0.0.1:8088/voice/chat -H "content-type: application/json" \
  -d '{"stream":true,"messages":[{"role":"user","content":"Bonjour !"}]}'
# TTS :
curl -s http://127.0.0.1:8088/voice/tts -H "content-type: application/json" \
  -d '{"text":"Bonjour."}' -o out.wav
```
(Depuis l'intérieur du bureau ; de l'extérieur, passe par `/voice/...` avec
l'auth du bureau. Ajoute `X-Voice-Token` si `BRAIN_SHIM_TOKEN` est posé.)

## Notes

- Latence à chaud : STT ~1 s → cerveau (dominant) → première voix ~2-4 s, puis
  lecture continue (synthèse N+1 pendant la lecture N). La première phrase est
  découpée agressivement pour que la voix démarre pendant que le cerveau écrit.
- Après ~2 min de silence les workers GPU s'endorment (gratuit) ; la page les
  réveille via `/voice/warm` dès l'ouverture — premier tour après pause ≈
  15-40 s. Cold start vLLM parfois plus long → `BRAIN_TIMEOUT_MS`.
- RunPod : les appels passent par `/run` + poll `/status` (jamais de `/runsync`
  tenu longtemps : stalls de gateway observés sur cold start).
- Pool GPU des endpoints : large (13 types, rapides d'abord) + `workersMax≥2`,
  sinon risque de throttle (quota compte RunPod : Σ workersMax ≤ 10).
