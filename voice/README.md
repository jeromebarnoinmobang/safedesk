# voice/ — parler à voix haute avec l'assistant SafeDesk

Tu parles → **Whisper (GPU serverless RunPod)** transcrit → le **cerveau**
répond en streaming → **Kyutai TTS 1.6B (GPU serverless)** lit la réponse en
français. La page micro (VAD maison, auto-stop au silence) marche sur Chrome,
Android et iOS Safari — aucune Web Speech API.

C'est la brique « LLM gardien vocal » de SafeDesk : un assistant à qui l'on
parle, qui explique sans jargon et met en garde contre les arnaques.
Code hérité du voice-brain de la fleet mobang (v2, prouvé e2e le 2026-07-10).

## Deux cerveaux au choix (`VOICE_BRAIN`)

| | `claude` (défaut) | `openai` |
|---|---|---|
| Quoi | CLI officiel `claude` (session chaude, streaming) | Tout endpoint OpenAI-compatible — cas nominal : **RunPod serverless vLLM** |
| Capacités | **Agentique** : vrais outils, MCP optionnel | Conversation pure (pas d'outils) |
| Contexte | Gardé par la session chaude | Historique glissant géré par le shim (`VOICE_HISTORY_TURNS`) |
| Coût | Abonnement Max (zéro clé API) | GPU serverless scale-to-zero (centimes) |
| Config | `CLAUDE_CODE_OAUTH_TOKEN` (`claude setup-token`) | `RUNPOD_LLM_ENDPOINT_ID` + `BRAIN_OPENAI_MODEL` (ou `BRAIN_OPENAI_BASE_URL` explicite) |

## Activer

```bash
cp voice/.env.example voice/.env   # puis remplir (cerveau + RunPod)
docker compose -f docker-compose.yml -f docker-compose.local.yml -f docker-compose.voice.yml up -d --build
```

La page vit sur `https://<ton-bureau>/voice/` — même auth que le bureau
(le nginx du conteneur desktop proxifie vers le sidecar `voice`).
`BRAIN_SHIM_TOKEN` n'est utile que si tu exposes le shim directement en public
(la page l'envoie alors en `X-Voice-Token`, URL clé en main `/voice/#t=<token>`).

## Les morceaux

| Fichier | Rôle |
|---|---|
| `brain-shim.mjs` | Le serveur : page `/voice/`, `/voice/chat` (+ façade OpenAI `/v1/chat/completions`), `/voice/stt` (blob micro → faster-whisper RunPod), `/voice/tts` (texte → Kyutai RunPod, fallback pocket-tts local), `/voice/warm` (préchauffage STT+TTS+LLM), `/health`. |
| `Dockerfile` | Image du cerveau (node:22 + `@anthropic-ai/claude-code`). |
| `../docker-compose.voice.yml` | Overlay compose : sidecar `voice` (+ `voice-tts` via `--profile tts-fallback`). |
| `claude-config/` | Settings + hook du cerveau claude (contexte second-brain optionnel). |
| `tts/` | Image du fallback voix local (Kyutai pocket-tts, CPU, français). |

## Tester

```bash
# santé (type de cerveau, backends audio) :
curl -s http://voice:8088/health
# cerveau (streame du texte) :
curl -N http://voice:8088/voice/chat -H "content-type: application/json" \
  -d '{"stream":true,"messages":[{"role":"user","content":"Bonjour !"}]}'
# TTS :
curl -s http://voice:8088/voice/tts -H "content-type: application/json" \
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
