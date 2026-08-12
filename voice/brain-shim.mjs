#!/usr/bin/env node
// =============================================================================
// brain-shim.mjs — assistant vocal SafeDesk : CERVEAU commutable + pipeline
// audio serverless RunPod (STT faster-whisper, TTS Kyutai 1.6B GPU).
// Importé du voice-brain de la fleet mobang (v2 LIVE 2026-07-10), adapté.
//
// CERVEAU (VOICE_BRAIN) :
//   claude (défaut) : le CLI `claude` sur abonnement Max — AUCUNE clé API,
//     zéro facturation token. Auth = CLAUDE_CODE_OAUTH_TOKEN (1 an). Agentique :
//     vrais outils (MCP optionnel). Session CHAUDE : un SEUL process
//     `claude --input-format stream-json --output-format stream-json` gardé
//     vivant → système + cache chargés UNE fois ; chaque tour = 1 message sur
//     stdin → réponse streamée (latence + ~90% de tokens en moins). Fallback
//     cold `claude -p` si VOICE_WARM=0 (ou si le process chaud meurt).
//   openai : n'importe quel endpoint OpenAI-compatible — cas nominal = LLM sur
//     RunPod SERVERLESS vLLM (RUNPOD_LLM_ENDPOINT_ID → l'URL /openai/v1 est
//     déduite), scale-to-zero. Le LLM est stateless → le shim garde un
//     historique glissant (VOICE_HISTORY_TURNS tours) et le renvoie à chaque
//     appel. Pas d'outils : conversation pure.
//   relay : cerveau EXTERNE par fichiers (VOICE_RELAY_DIR) — n'importe quel
//     agent répond via mcp-voice.mjs (outils voice_wait/voice_answer) ou en
//     écrivant a-<id>.txt à la main. C'est le mode « une session Claude Code
//     est le cerveau ».
//
// AUDIO (remplace la Web Speech API navigateur, 2026-07-10) :
//   /voice/stt  : blob micro (webm/opus ou mp4) → base64 → endpoint RunPod
//                 faster-whisper (model turbo, fr) → {text}. ~0.5-1s à chaud.
//   /voice/tts  : texte → endpoint RunPod Kyutai TTS 1.6B (voix française
//                 kyutai/tts-voices) → WAV. Fallback = pocket-tts local (CPU)
//                 si le serverless échoue et que VOICE_TTS_URL est configuré.
//   /voice/warm : préchauffe les 2 endpoints (fire-and-forget) — appelé à
//                 l'ouverture de la page pour absorber le cold start pendant
//                 que Jérôme lit l'écran.
// La page /voice capture le micro en MediaRecorder + VAD maison (auto-stop au
// silence) — plus aucune dépendance à SpeechRecognition/Chrome.
// =============================================================================
import http from 'node:http';
import fs from 'node:fs';
import { spawn } from 'node:child_process';
import process from 'node:process';

const PORT = Number(process.env.BRAIN_SHIM_PORT || 8088);
const MODEL = process.env.VOICE_MODEL || 'opus';
const EFFORT = process.env.VOICE_EFFORT || 'max';
const SHIM_TOKEN = process.env.BRAIN_SHIM_TOKEN || '';
const MCP_URL = process.env.SECOND_BRAIN_MCP_URL || '';
const MCP_TOKEN = process.env.SECOND_BRAIN_MCP_TOKEN || '';
const PLANE_PROJECT = process.env.VOICE_PLANE_PROJECT || '';
const CLAUDE_BIN = process.env.CLAUDE_BIN || 'claude';
const TIMEOUT_MS = Number(process.env.BRAIN_TIMEOUT_MS || process.env.CLAUDE_TIMEOUT_MS || 120000);
const IDLE_MS = Number(process.env.WARM_IDLE_MS || 25 * 60 * 1000);
const WARM = process.env.VOICE_WARM !== '0';
const SB = !!(MCP_TOKEN && MCP_URL);

// ---- cerveau commutable -----------------------------------------------------
// claude = CLI claude (Max, agentique) · openai = endpoint OpenAI-compatible
// (RunPod serverless vLLM ou autre). Ces réglages ne servent qu'en mode openai.
const BRAIN = (process.env.VOICE_BRAIN || 'claude').toLowerCase();
const LLM_EP = process.env.RUNPOD_LLM_ENDPOINT_ID || '';
const OAI_BASE = (process.env.BRAIN_OPENAI_BASE_URL || '').replace(/\/+$/, '')
  || (LLM_EP ? `https://api.runpod.ai/v2/${LLM_EP}/openai/v1` : '');
// RunPod serverless s'authentifie avec la clé de compte RunPod → défaut naturel.
const OAI_KEY = process.env.BRAIN_OPENAI_API_KEY || process.env.RUNPOD_API_KEY || '';
const OAI_MODEL = process.env.BRAIN_OPENAI_MODEL || '';
const OAI_MAX_TOKENS = Number(process.env.BRAIN_OPENAI_MAX_TOKENS || 700);
const HISTORY_TURNS = Number(process.env.VOICE_HISTORY_TURNS || 8);
const OAI_OK = !!(OAI_BASE && OAI_MODEL);
// relay = cerveau EXTERNE. Deux transports :
//   - DISTANT (VOICE_RELAY_URL posé) : le shim POUSSE la phrase au hub vocal du
//     second-brain (POST /voice/ask puis long-poll /voice/answer/<id>) — un
//     agent MCP répond via voice_wait/voice_answer. Marche de partout (le
//     bureau n'a besoin d'AUCUNE entrée réseau).
//   - LOCAL (défaut) : fichiers q-<id>.json / a-<id>.txt dans VOICE_RELAY_DIR,
//     consommés par mcp-voice.mjs ou /voice/agent/* (agent co-localisé).
const RELAY_DIR = process.env.VOICE_RELAY_DIR || '/tmp/safedesk-voice-relay';
const RELAY_URL = (process.env.VOICE_RELAY_URL || '').replace(/\/+$/, '');
const RELAY_HUB_TOKEN = process.env.VOICE_RELAY_TOKEN || '';

// ---- audio serverless (RunPod) ----------------------------------------------
const RUNPOD_KEY = process.env.RUNPOD_API_KEY || '';
const STT_EP = process.env.RUNPOD_STT_ENDPOINT_ID || '';
const TTS_EP = process.env.RUNPOD_TTS_ENDPOINT_ID || '';
const STT_MODEL = process.env.VOICE_STT_MODEL || 'turbo'; // large-v3-turbo, multilingue
const STT_LANG = process.env.VOICE_STT_LANGUAGE || 'fr';
// initial_prompt = biais de vocabulaire (surchargez avec vos noms propres).
const STT_PROMPT = process.env.VOICE_STT_PROMPT
  || "Conversation en français avec l'assistant vocal SafeDesk.";
const STT_TIMEOUT = Number(process.env.STT_TIMEOUT_MS || 90000);
const TTS_TIMEOUT = Number(process.env.TTS_TIMEOUT_MS || 90000);
// Voix Kyutai (chemin dans kyutai/tts-voices). developpeuse-3 = voix française
// du démo Unmute — prouvée intelligible (round-trip TTS→STT exact, 2026-07-10).
const RP_TTS_VOICE = process.env.RUNPOD_TTS_VOICE || 'unmute-prod-website/developpeuse-3.wav';
// Fallback local pocket-tts (CPU, conteneur voice-tts) — utilisé si RunPod HS.
// Même défaut que l'ancienne version (les .env existants ne définissent pas la
// clé) ; mettre VOICE_TTS_URL=off pour désactiver le fallback explicitement.
const LOCAL_TTS_URL = (process.env.VOICE_TTS_URL ?? 'http://voice-tts:8000') === 'off' ? '' : (process.env.VOICE_TTS_URL || 'http://voice-tts:8000');
const LOCAL_TTS_VOICE = process.env.VOICE_TTS_VOICE || 'estelle';

// Persona par défaut = le gardien vocal SafeDesk (l'origine du nom : un LLM
// qui se pilote à la voix et veille à la sécurité de la personne).
const USER_NAME = process.env.VOICE_USER_NAME || '';
const WHO = USER_NAME ? `Tu parles avec ${USER_NAME}.` : 'Tu parles avec la personne qui utilise ce bureau.';
const STYLE_VOCAL = `STYLE VOCAL (tu es lu à voix haute par une synthèse) : phrases courtes, ton naturel et chaleureux, JAMAIS de listes à puces ni de markdown, pas de pavés. Si tu énumères, dis-le en une phrase fluide.`;
const GARDIEN = `Tu es l'assistant vocal de SafeDesk, un espace numérique pensé pour rester SÛR et SIMPLE, notamment pour des personnes peu à l'aise avec l'informatique. ${WHO}
Tu es un GARDIEN bienveillant : tu expliques sans jargon, tu rassures sans infantiliser, une chose à la fois. Si la personne décrit quelque chose de suspect (alerte plein écran, demande de carte bancaire, gain inattendu, inconnu pressant), tu la mets en garde clairement et tu lui dis de ne rien payer ni communiquer.`;
const ANTI_INVENTION = `Tu n'inventes JAMAIS un chiffre, une date ou un fait personnel : si tu ne sais pas, dis-le.`;
const DEFAULT_SYSTEM_PROMPT = BRAIN === 'openai'
  ? `${GARDIEN}
Tu n'as PAS d'outils ni d'accès au bureau : tu discutes, tu expliques, tu guides pas à pas.
${STYLE_VOCAL}
${ANTI_INVENTION}`
  : `${GARDIEN}
Tu es Claude Code : tu as de VRAIS outils et tu peux AGIR, pas seulement discuter. Quand on te donne une commande, une question ou une tâche, EXÉCUTE-la avec tes outils PUIS dis en une phrase ce que tu as fait ou trouvé. Agis d'abord, parle ensuite — brièvement.
${STYLE_VOCAL}
${SB ? `MÉMOIRE & TÂCHES (outils second-brain) :
- Si le contexte de la personne (sa vie, ses projets, ses chiffres) est utile, utilise l'outil "recall" (scope personal) — discrètement, sans le commenter.
- Quand la personne exprime une tâche ou une intention, crée-la avec "create_task"${PLANE_PROJECT ? ` (project_identifier="${PLANE_PROJECT}", type="task", eisenhower_quadrant Q1-Q4)` : ''}, PUIS confirme oralement en une phrase. Ne décris pas l'outil, fais-le en fond.
` : ''}${ANTI_INVENTION}`;
// Surchargeable via SHIM_SYSTEM_PROMPT ("" → moteur neutre, sans persona vocale).
const SYSTEM_PROMPT = process.env.SHIM_SYSTEM_PROMPT ?? DEFAULT_SYSTEM_PROMPT;

function mcpConfigArg() {
  if (!SB) return null;
  return JSON.stringify({
    mcpServers: { 'second-brain': { type: 'http', url: MCP_URL, headers: { Authorization: `Bearer ${MCP_TOKEN}` } } },
  });
}

// ---- helpers ----------------------------------------------------------------
function send(res, code, obj) {
  res.writeHead(code, { 'content-type': 'application/json', 'cache-control': 'no-store' });
  res.end(JSON.stringify(obj));
}
function bearerOk(req) {
  if (!SHIM_TOKEN) return true;
  // X-Voice-Token = chemin de la page SafeDesk : derrière le nginx du bureau,
  // Authorization porte déjà le Basic de l'auth bureau (un Bearer l'écraserait
  // et ferait rejeter la requête par nginx AVANT le proxy). Bearer reste
  // accepté pour les clients API directs (OpenAI-compat).
  if ((req.headers['x-voice-token'] || '') === SHIM_TOKEN) return true;
  return (req.headers['authorization'] || '').replace(/^Bearer\s+/i, '') === SHIM_TOKEN;
}
function readBody(req) {
  return new Promise((resolve) => { let b = ''; req.on('data', (c) => (b += c)); req.on('end', () => resolve(b)); });
}
// Corps BINAIRE (upload micro). Cap 15 Mo (≈ >30 min d'opus 48kbps : large).
function readBodyBuffer(req, maxBytes = 15 * 1024 * 1024) {
  return new Promise((resolve, reject) => {
    const parts = []; let n = 0;
    req.on('data', (c) => {
      n += c.length;
      if (n > maxBytes) { reject(new Error('body_too_large')); try { req.destroy(); } catch {} ; return; }
      parts.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(parts)));
    req.on('error', reject);
  });
}
function lastUserText(messages) {
  for (let i = (messages || []).length - 1; i >= 0; i--) {
    const m = messages[i];
    if (m.role !== 'user') continue;
    const c = typeof m.content === 'string' ? m.content : Array.isArray(m.content) ? m.content.map((p) => p.text || '').join(' ') : '';
    if (c.trim()) return c.trim();
  }
  return 'Bonjour.';
}
const EFFECTIVE_MODEL = BRAIN === 'openai' ? OAI_MODEL : (BRAIN === 'relay' ? 'relay' : MODEL);
function sseChunk(id, delta, finish = null) {
  return `data: ${JSON.stringify({
    id, object: 'chat.completion.chunk', created: 0, model: EFFECTIVE_MODEL,
    choices: [{ index: 0, delta: delta ? { content: delta } : {}, finish_reason: finish }],
  })}\n\n`;
}
const baseArgs = () => {
  const a = ['--verbose', '--include-partial-messages', '--permission-mode', 'bypassPermissions'];
  if (SYSTEM_PROMPT) a.push('--append-system-prompt', SYSTEM_PROMPT);
  a.push('--model', MODEL, '--effort', EFFORT);
  const mcp = mcpConfigArg();
  if (mcp) a.push('--mcp-config', mcp);
  return a;
};

// ---- RunPod serverless : submit /run (rapide) puis poll /status --------------
// PAS de /runsync tenu longtemps : des stalls de gateway ont été observés sur
// cold start (abort ~25s) — le couple /run + poll est le chemin prouvé.
const rpHeaders = () => ({ authorization: `Bearer ${RUNPOD_KEY}`, 'content-type': 'application/json' });
async function runpodRun(ep, input, timeoutMs) {
  const base = `https://api.runpod.ai/v2/${ep}`;
  const deadline = Date.now() + timeoutMs;
  const r = await fetch(`${base}/run`, {
    method: 'POST', headers: rpHeaders(), body: JSON.stringify({ input }),
    signal: AbortSignal.timeout(20000),
  });
  let j = await r.json();
  const jobId = j?.id;
  if (!jobId) throw new Error(`runpod submit failed: ${JSON.stringify(j ?? null).slice(0, 200)}`);
  for (;;) {
    if (j.status === 'COMPLETED') return j.output;
    if (j.status === 'FAILED' || j.status === 'CANCELLED' || j.status === 'TIMED_OUT') {
      throw new Error(`runpod ${j.status}: ${JSON.stringify(j.output ?? j.error ?? null).slice(0, 300)}`);
    }
    if (Date.now() > deadline) {
      fetch(`${base}/cancel/${jobId}`, { method: 'POST', headers: rpHeaders() }).catch(() => {});
      throw new Error(`runpod timeout (${j.status || 'unknown'} after ${Math.round(timeoutMs / 1000)}s)`);
    }
    await new Promise((s) => setTimeout(s, 700));
    try {
      const sr = await fetch(`${base}/status/${jobId}`, { headers: rpHeaders(), signal: AbortSignal.timeout(15000) });
      j = await sr.json();
    } catch { /* erreur de poll transitoire → on retente jusqu'au deadline */ }
  }
}
// WAV de silence (16 kHz mono 16-bit) pour préchauffer le worker whisper : le
// job force le chargement du modèle en cache pendant que Jérôme lit la page.
function silenceWavB64(ms = 250) {
  const sr = 16000, n = Math.floor((sr * ms) / 1000);
  const b = Buffer.alloc(44 + n * 2);
  b.write('RIFF', 0); b.writeUInt32LE(36 + n * 2, 4); b.write('WAVE', 8);
  b.write('fmt ', 12); b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(1, 22);
  b.writeUInt32LE(sr, 24); b.writeUInt32LE(sr * 2, 28); b.writeUInt16LE(2, 32); b.writeUInt16LE(16, 34);
  b.write('data', 36); b.writeUInt32LE(n * 2, 40);
  return b.toString('base64');
}
let lastWarm = 0;

// ---- session CHAUDE (process claude persistant, streaming stdin) ------------
class WarmBrain {
  constructor() { this.child = null; this.queue = Promise.resolve(); this.idleTimer = null; this.buf = ''; this.onLine = null; }
  spawnChild() {
    const args = ['--input-format', 'stream-json', '--output-format', 'stream-json', ...baseArgs()];
    const child = spawn(CLAUDE_BIN, args, { env: { ...process.env }, stdio: ['pipe', 'pipe', 'pipe'] });
    // Sans listener, un EPIPE/EOF sur stdin (claude meurt pendant qu'un write
    // est en vol) émet un 'error' non géré → crash du shim entier.
    child.stdin.on('error', (e) => console.error('[claude] stdin', e.message));
    child.stderr.on('data', (d) => { const s = d.toString(); if (s.trim()) console.error('[claude]', s.slice(0, 300)); });
    child.on('exit', (code) => { console.error(`[claude] warm exit (${code}) — respawn next turn`); if (this.child === child) this.child = null; });
    child.on('error', (e) => { console.error('[claude] spawn', e.message); if (this.child === child) this.child = null; });
    this.child = child; this.buf = ''; this.onLine = null;
    child.stdout.on('data', (d) => this._feed(d));
    return child;
  }
  ensure() { if (!this.child || this.child.exitCode !== null) this.spawnChild(); return this.child; }
  _feed(d) {
    this.buf += d.toString();
    let nl;
    while ((nl = this.buf.indexOf('\n')) >= 0) {
      const line = this.buf.slice(0, nl); this.buf = this.buf.slice(nl + 1);
      if (line.trim() && this.onLine) this.onLine(line);
    }
  }
  ask(promptText, onDelta) {
    const run = this.queue.then(() => this._askNow(promptText, onDelta));
    this.queue = run.catch(() => {});
    return run;
  }
  _askNow(promptText, onDelta) {
    return new Promise((resolve) => {
      const child = this.ensure();
      this._resetIdle();
      let full = '', done = false;
      const finish = () => { if (done) return; done = true; clearTimeout(killer); this.onLine = null; resolve(full); };
      const killer = setTimeout(() => { console.error('[claude] turn timeout — recycle'); try { child.kill('SIGKILL'); } catch {} ; this.child = null; finish(); }, TIMEOUT_MS);
      this.onLine = (line) => {
        let o; try { o = JSON.parse(line); } catch { return; }
        if (o.type === 'stream_event' && o.event?.delta?.type === 'text_delta') {
          const t = o.event.delta.text || '';
          if (t) { full += t; onDelta(t); }
        } else if (o.type === 'result') { finish(); }
      };
      child.stdin.write(JSON.stringify({ type: 'user', message: { role: 'user', content: [{ type: 'text', text: promptText }] } }) + '\n');
    });
  }
  _resetIdle() {
    if (this.idleTimer) clearTimeout(this.idleTimer);
    this.idleTimer = setTimeout(() => { try { this.child?.stdin?.end(); this.child?.kill('SIGTERM'); } catch {} ; this.child = null; }, IDLE_MS);
  }
}
const brain = new WarmBrain();
if (BRAIN === 'claude' && WARM && process.env.CLAUDE_CODE_OAUTH_TOKEN) brain.ensure(); // cold start payé UNE fois au boot

// ---- fallback FROID (claude -p par appel) ----------------------------------
function runClaudeCold(promptText, onDelta) {
  return new Promise((resolve) => {
    const args = ['-p', promptText, '--output-format', 'stream-json', ...baseArgs()];
    let full = '', buf = '', done = false;
    const child = spawn(CLAUDE_BIN, args, { env: { ...process.env }, stdio: ['ignore', 'pipe', 'pipe'] });
    const finish = () => { if (done) return; done = true; clearTimeout(killer); resolve(full); };
    const killer = setTimeout(() => { try { child.kill('SIGKILL'); } catch {} ; finish(); }, TIMEOUT_MS);
    child.stdout.on('data', (d) => {
      buf += d.toString(); let nl;
      while ((nl = buf.indexOf('\n')) >= 0) {
        const line = buf.slice(0, nl); buf = buf.slice(nl + 1);
        if (!line.trim()) continue;
        let o; try { o = JSON.parse(line); } catch { continue; }
        if (o.type === 'stream_event' && o.event?.delta?.type === 'text_delta') { const t = o.event.delta.text || ''; if (t) { full += t; onDelta(t); } }
      }
    });
    child.stderr.on('data', (d) => { const s = d.toString(); if (s.trim()) console.error('[claude-cold]', s.slice(0, 200)); });
    child.on('close', () => finish());
    child.on('error', (e) => { console.error('[claude-cold] spawn', e.message); finish(); });
  });
}

// ---- cerveau OpenAI-compat (RunPod serverless vLLM ou autre) ----------------
// Stateless côté LLM → historique glissant côté shim (HISTORY_TURNS derniers
// tours), renvoyé à chaque appel avec le system prompt.
const history = [];
function pushHistory(role, content) {
  history.push({ role, content });
  const max = HISTORY_TURNS * 2;
  if (history.length > max) history.splice(0, history.length - max);
}
async function askOpenAI(userText, onDelta) {
  pushHistory('user', userText);
  let full = '';
  try {
    const r = await fetch(`${OAI_BASE}/chat/completions`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...(OAI_KEY ? { authorization: `Bearer ${OAI_KEY}` } : {}) },
      body: JSON.stringify({
        model: OAI_MODEL, stream: true, max_tokens: OAI_MAX_TOKENS,
        messages: [...(SYSTEM_PROMPT ? [{ role: 'system', content: SYSTEM_PROMPT }] : []), ...history],
      }),
      // Couvre tout le tour, cold start RunPod compris (le worker se réveille
      // pendant que la requête attend) — monter BRAIN_TIMEOUT_MS si besoin.
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (!r.ok || !r.body) {
      const t = await r.text().catch(() => '');
      throw new Error(`llm ${r.status}: ${t.slice(0, 200)}`);
    }
    const dec = new TextDecoder();
    let sse = '';
    for await (const chunk of r.body) {
      sse += dec.decode(chunk, { stream: true });
      let nl;
      while ((nl = sse.indexOf('\n')) >= 0) {
        const line = sse.slice(0, nl).trim(); sse = sse.slice(nl + 1);
        if (!line.startsWith('data:')) continue;
        const data = line.slice(5).trim();
        if (!data || data === '[DONE]') continue;
        let o; try { o = JSON.parse(data); } catch { continue; }
        const t = o.choices?.[0]?.delta?.content || '';
        if (t) { full += t; onDelta(t); }
      }
    }
  } catch (e) {
    // tour raté → on retire le message user (sinon il polluerait le tour suivant)
    if (!full) history.pop(); else pushHistory('assistant', full);
    throw e;
  }
  pushHistory('assistant', full);
  return full;
}
// ---- cerveau RELAY, transport DISTANT (hub vocal second-brain) ---------------
const DESK_NAME = process.env.VOICE_DESK_NAME || process.env.HOSTNAME || 'safedesk';
async function askRelayRemote(userText, onDelta) {
  const hubHeaders = { 'content-type': 'application/json', 'x-voice-relay-token': RELAY_HUB_TOKEN };
  // annulation best-effort : un tour abandonné ne doit pas masquer les suivants
  const cancelTurn = (id) => {
    fetch(`${RELAY_URL}/voice/cancel/${id}`, { method: 'POST', headers: hubHeaders, signal: AbortSignal.timeout(8000) }).catch(() => {});
  };
  let r;
  try {
    r = await fetch(`${RELAY_URL}/voice/ask`, {
      method: 'POST', headers: hubHeaders, body: JSON.stringify({ text: userText, source: DESK_NAME }),
      signal: AbortSignal.timeout(15000),
    });
  } catch (e) { throw new Error(`hub vocal injoignable: ${String(e.message || e).slice(0, 120)}`); }
  if (!r.ok) throw new Error(`hub vocal ${r.status}: ${(await r.text().catch(() => '')).slice(0, 200)}`);
  const { id } = await r.json().catch(() => { throw new Error('hub vocal: réponse illisible'); });
  if (!id) throw new Error('hub vocal: pas d\'id retourné');
  const deadline = Date.now() + TIMEOUT_MS;
  try {
    for (;;) {
      const remain = deadline - Date.now();
      if (remain <= 0) { cancelTurn(id); throw new Error("relay: le cerveau externe n'a pas répondu à temps"); }
      const pollS = Math.max(2, Math.min(25, Math.floor(remain / 1000)));
      const pr = await fetch(`${RELAY_URL}/voice/answer/${id}?timeout_s=${pollS}`, {
        headers: hubHeaders, signal: AbortSignal.timeout((pollS + 15) * 1000),
      }).catch((e) => { throw new Error(`hub vocal injoignable: ${String(e.message || e).slice(0, 120)}`); });
      if (pr.status === 404) throw new Error('relay: tour expiré côté hub');
      if (!pr.ok) throw new Error(`hub vocal ${pr.status}`);
      // un 200 non-JSON (proxy intermédiaire, portail captif) = erreur de
      // transport, PAS un {} silencieux qui martèlerait le hub sans pause
      const j = await pr.json().catch(() => { throw new Error('hub vocal: réponse illisible'); });
      if (typeof j.answer === 'string' && j.answer.trim()) { onDelta(j.answer); return j.answer; }
      await new Promise((s) => setTimeout(s, 300)); // garde-fou anti-martèlement
    }
  } catch (e) {
    // toute sortie en erreur (sauf tour déjà expiré côté hub) → cancel best-effort
    if (!String(e.message || '').includes('expiré')) cancelTurn(id);
    throw e;
  }
}

// ---- cerveau RELAY, transport LOCAL (fichiers) -------------------------------
// Dépose q-<id>.json et attend a-<id>.txt (écrit par l'agent — ex. l'outil MCP
// voice_answer local, ou une session Claude Code qui surveille le dossier).
let relaySeq = 0;
async function askRelay(userText, onDelta) {
  if (RELAY_URL) return askRelayRemote(userText, onDelta);
  fs.mkdirSync(RELAY_DIR, { recursive: true });
  const id = `${Date.now()}-${++relaySeq}`;
  const qf = `${RELAY_DIR}/q-${id}.json`, af = `${RELAY_DIR}/a-${id}.txt`;
  fs.writeFileSync(qf, JSON.stringify({ id, text: userText, ts: new Date().toISOString() }) + '\n');
  const deadline = Date.now() + TIMEOUT_MS;
  try {
    for (;;) {
      if (fs.existsSync(af)) {
        await new Promise((s) => setTimeout(s, 150)); // laisse le writer finir
        const full = fs.readFileSync(af, 'utf8').trim();
        try { fs.unlinkSync(af); } catch {}
        if (full) onDelta(full);
        return full;
      }
      if (Date.now() > deadline) throw new Error("relay: le cerveau externe n'a pas répondu à temps");
      await new Promise((s) => setTimeout(s, 300));
    }
  } finally { try { fs.unlinkSync(qf); } catch {} }
}

// Dispatch unique : les handlers HTTP ne connaissent pas le type de cerveau.
function askBrain(userText, onDelta) {
  if (BRAIN === 'openai') return askOpenAI(userText, onDelta);
  if (BRAIN === 'relay') return askRelay(userText, onDelta);
  return WARM ? brain.ask(userText, onDelta) : runClaudeCold(userText, onDelta);
}
function brainReady() {
  if (BRAIN === 'openai') return OAI_OK ? null : 'openai: BRAIN_OPENAI_BASE_URL (ou RUNPOD_LLM_ENDPOINT_ID) et BRAIN_OPENAI_MODEL requis';
  if (BRAIN === 'relay') {
    if (RELAY_URL && !RELAY_HUB_TOKEN) return 'relay: VOICE_RELAY_URL posé sans VOICE_RELAY_TOKEN (le hub répondra 503)';
    return null;
  }
  return process.env.CLAUDE_CODE_OAUTH_TOKEN ? null : 'claude: CLAUDE_CODE_OAUTH_TOKEN manquant';
}

// ---- page vocale (micro MediaRecorder + VAD maison, zéro Web Speech API) ----
const VOICE_HTML = `<!doctype html><html lang=fr><head><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1,maximum-scale=1,viewport-fit=cover"><title>Voix — SafeDesk</title>
<style>:root{color-scheme:dark}*{box-sizing:border-box}
body{margin:0;font:16px/1.5 system-ui,-apple-system,sans-serif;background:#0f1115;color:#e6e6e6;height:100dvh;display:flex;flex-direction:column}
header{padding:13px 16px;background:#161922;border-bottom:1px solid #262b36;font-weight:600;color:#8aa0ff;text-align:center;flex:none}
#log{flex:1;overflow-y:auto;padding:16px;display:flex;flex-direction:column;gap:10px}
.msg{max-width:85%;padding:10px 13px;border-radius:14px;white-space:pre-wrap;overflow-wrap:anywhere}
.me{align-self:flex-end;background:#2d6cdf;color:#fff;border-bottom-right-radius:4px}
.bot{align-self:flex-start;background:#1c2230;border:1px solid #262b36;border-bottom-left-radius:4px}
.sys{align-self:center;color:#7f8aa3;font-size:13px;text-align:center;max-width:94%}
footer{flex:none;padding:12px 16px calc(12px + env(safe-area-inset-bottom));background:#161922;border-top:1px solid #262b36}
.state{text-align:center;font-size:14px;color:#9aa6bd;margin-bottom:10px;min-height:20px}
.mic{display:block;margin:0 auto;width:92px;height:92px;border-radius:50%;border:none;font-size:36px;background:#2d6cdf;color:#fff;cursor:pointer;transition:background .15s;-webkit-tap-highlight-color:transparent}
.mic.listening{background:#e0455e}
.mic.busy{background:#3a4150;cursor:default}
.opts{display:flex;justify-content:center;gap:20px;margin-top:12px;font-size:14px;color:#9aa6bd}
.opts label{display:flex;align-items:center;gap:6px;cursor:pointer}
#txtrow{display:flex;gap:8px;margin-top:12px}
#txt{flex:1;padding:11px;border-radius:10px;border:1px solid #333b4d;background:#0f1115;color:#e6e6e6;font-size:16px}
#send{padding:0 16px;border-radius:10px;border:none;background:#2d6cdf;color:#fff;font-weight:600;font-size:18px}</style></head><body>
<header>🎙 Assistant vocal — SafeDesk</header>
<div id=log></div>
<footer>
 <div class=state id=state>…</div>
 <button class=mic id=mic>🎤</button>
 <div class=opts><label><input type=checkbox id=hands> mains libres</label><label><input type=checkbox id=tts checked> voix</label></div>
 <div id=txtrow><input id=txt placeholder="ou écris ici…" autocomplete=off><button id=send>↑</button></div>
</footer>
<script>
// La page vit sous un sous-chemin (nginx SafeDesk : /voice/) ou à la racine
// d'un vhost dédié : toutes les routes API sont relatives à son emplacement.
var base=location.pathname.replace(/\\/+$/,'');
var token=localStorage.getItem('voiceToken')||'';
// URL "clé en main" : /voice#t=<token> — le fragment ne quitte JAMAIS le
// navigateur (ni serveur, ni logs proxy). Stocké puis effacé de l'URL.
if(location.hash&&location.hash.indexOf('#t=')===0){token=decodeURIComponent(location.hash.slice(3));localStorage.setItem('voiceToken',token);try{history.replaceState(null,'',location.pathname)}catch(e){}}
// Token jamais forcé : derrière l'auth du bureau SafeDesk, BRAIN_SHIM_TOKEN est
// souvent vide. S'il est requis, le premier 401 le demandera. Le token part
// dans X-Voice-Token (PAS Authorization : déjà pris par l'auth Basic du bureau).
function hdrs(extra){var h=extra||{};if(token)h['x-voice-token']=token;return h}
function askToken(){token=prompt('Token vocal (BRAIN_SHIM_TOKEN)')||'';localStorage.setItem('voiceToken',token)}
var $=function(i){return document.getElementById(i)};
var logEl=$('log'),stateEl=$('state'),mic=$('mic'),handsEl=$('hands'),ttsEl=$('tts'),txt=$('txt'),sendBtn=$('send');
var busy=false,speaking=false,inflight=0,gen=0,ttsQueue=[],synthBusy=false,playQ=[],playing=false,audioEl=null,audioUnlocked=false,buf='',spokenLen=0,botEl=null,ttsWarned=false;
var stream=null,ac=null,an=null,anBuf=null,anBuf8=null,rec=null,listening=false,starting=false,vadT=null,warmed=false;
function setState(s){stateEl.textContent=s}
function add(cls,t){var d=document.createElement('div');d.className='msg '+cls;d.textContent=t;logEl.appendChild(d);logEl.scrollTop=logEl.scrollHeight;return d}
add('sys','Appuie sur le micro et parle. Reconnaissance (Whisper) et voix (Kyutai) tournent sur GPU serverless : après une pause, la première réponse prend quelques secondes de réveil — ensuite c\\'est fluide. Coche « mains libres » pour enchaîner sans toucher l\\'écran.');
// ---- préchauffage des workers GPU (absorbé pendant que tu lis l'écran) ----
function warm(){if(warmed)return;warmed=true;setTimeout(function(){warmed=false},90000);
 fetch(base+'/warm',{method:'POST',headers:hdrs()}).catch(function(){})}
warm();
// ---- lecture voix : synthèse sérialisée + file de lecture (audio continu) ----
function afterSpeak(){if(inflight<=0)speaking=false;if(busy||inflight>0)return;if(handsEl.checked){startListen()}else setState('prêt — appuie pour parler')}
function ensureAudio(){if(!audioEl){audioEl=new Audio();audioEl.setAttribute('playsinline','');audioEl.preload='auto'}if(!audioUnlocked){audioUnlocked=true;try{audioEl.src='data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBAAAAABAAEARKwAAIhYAQACABAAZGF0YQAAAAA=';var p=audioEl.play();if(p&&p.catch)p.catch(function(){})}catch(e){}}return audioEl}
function playClip(url){playQ.push(url);if(!playing)playClipNext()}
function playClipNext(){
 if(!playQ.length){playing=false;return}
 playing=true;var url=playQ.shift();var el=ensureAudio();
 var called=false;
 var done=function(){if(called)return;called=true;try{URL.revokeObjectURL(url)}catch(e){}inflight=Math.max(0,inflight-1);afterSpeak();playClipNext()};
 el.onended=done;el.onerror=done;el.src=url;var p=el.play();if(p&&p.catch)p.catch(done);
}
function pumpSynth(){
 if(synthBusy||!ttsQueue.length)return;
 synthBusy=true;var g=gen,t=ttsQueue.shift();
 fetch(base+'/tts',{method:'POST',headers:hdrs({'content-type':'application/json'}),body:JSON.stringify({text:t})})
  .then(function(r){if(!r.ok)throw new Error('tts '+r.status);return r.blob()})
  .then(function(b){if(g!==gen)return;synthBusy=false;playClip(URL.createObjectURL(b));pumpSynth()})
  .catch(function(e){if(g!==gen)return;synthBusy=false;inflight=Math.max(0,inflight-1);if(!ttsWarned){ttsWarned=true;add('sys','⚠ voix indispo ('+e.message+') — lis la réponse à l\\'écran')}afterSpeak();pumpSynth()});
}
function speak(t){if(!ttsEl.checked||!t.trim())return;ttsQueue.push(t);inflight++;speaking=true;setState('🔊 voix…');pumpSynth()}
function stopAudio(){gen++;ttsQueue=[];playQ.forEach(function(u){try{URL.revokeObjectURL(u)}catch(e){}});playQ=[];if(audioEl){try{audioEl.pause()}catch(e){}}playing=false;synthBusy=false;inflight=0;speaking=false}
function flush(fin){
 var pend=buf.slice(spokenLen),i,idx=-1,c;
 if(fin){if(pend.trim())speak(pend);spokenLen=buf.length;return}
 for(i=pend.length-1;i>=0;i--){c=pend.charAt(i);if(c==='.'||c==='!'||c==='?'||c==='…'||c===':'||c==='\\n'){idx=i;break}}
 if(idx<0&&spokenLen===0){
  // premier morceau du tour : découpe agressive (virgule, ou coupe au mot vers
  // 110 caractères) pour que la voix DÉMARRE pendant que le cerveau écrit.
  for(i=pend.length-1;i>=30;i--){c=pend.charAt(i);if(c===','||c===';'){idx=i;break}}
  if(idx<0&&pend.length>110){for(i=109;i>=60;i--){if(pend.charAt(i)===' '){idx=i;break}}}
 }
 if(idx>=0){var ch=pend.slice(0,idx+1);if(ch.trim())speak(ch);spokenLen+=idx+1}
}
function ask(userText){
 if(!userText.trim()||busy)return;
 stopAudio();add('me',userText);busy=true;mic.classList.add('busy');setState('🧠 réflexion…');buf='';spokenLen=0;botEl=null;ttsWarned=false;
 fetch(base+'/chat',{method:'POST',headers:hdrs({'content-type':'application/json'}),body:JSON.stringify({model:'voice',stream:true,messages:[{role:'user',content:userText}]})})
 .then(function(r){
  if(!r.ok){if(r.status===401)askToken();throw new Error('HTTP '+r.status+(r.status===401?' — token mis à jour, réessaie':''));}
  var rd=r.body.getReader(),dec=new TextDecoder(),sse='';
  function pump(){return rd.read().then(function(res){
   if(res.done){flush(true);endTurn();return}
   sse+=dec.decode(res.value,{stream:true});var parts=sse.split('\\n\\n');sse=parts.pop();
   parts.forEach(function(b){
    var ln=b.split('\\n').filter(function(l){return l.indexOf('data:')===0})[0];if(!ln)return;
    var data=ln.slice(5).trim();if(data==='[DONE]')return;
    try{var o=JSON.parse(data);var t=o.choices&&o.choices[0]&&o.choices[0].delta&&o.choices[0].delta.content;if(t){buf+=t;if(!botEl)botEl=add('bot','');botEl.textContent=buf;logEl.scrollTop=logEl.scrollHeight;flush(false)}}catch(e){}
   });return pump();
  })}
  return pump();
 }).catch(function(e){endTurn();add('sys','⚠ '+e.message);setState('erreur — réessaie')});
}
function endTurn(){busy=false;mic.classList.remove('busy');afterSpeak()}
// ---- capture micro : MediaRecorder + VAD énergie (auto-stop au silence) ----
function pickMime(){var c=['audio/webm;codecs=opus','audio/webm','audio/mp4'];
 if(!window.MediaRecorder)return null;
 for(var i=0;i<c.length;i++){try{if(MediaRecorder.isTypeSupported(c[i]))return c[i]}catch(e){}}
 return ''}
function rmsNow(){
 if(an.getFloatTimeDomainData){if(!anBuf)anBuf=new Float32Array(an.fftSize);an.getFloatTimeDomainData(anBuf);var s=0,i;for(i=0;i<anBuf.length;i++)s+=anBuf[i]*anBuf[i];return Math.sqrt(s/anBuf.length)}
 if(!anBuf8)anBuf8=new Uint8Array(an.fftSize);an.getByteTimeDomainData(anBuf8);var s2=0,j,v;for(j=0;j<anBuf8.length;j++){v=(anBuf8[j]-128)/128;s2+=v*v}return Math.sqrt(s2/anBuf8.length)}
function startListen(){
 if(starting||listening||busy||speaking)return;
 warm();
 var mime=pickMime();
 if(mime===null){setState('MediaRecorder absent — mets ton navigateur à jour, ou écris en bas');return}
 starting=true;
 // flux mort (iOS coupe la piste : veille, appel, autre app) → réacquérir
 if(stream&&stream.getTracks().some(function(t){return t.readyState==='ended'})){
  try{stream.getTracks().forEach(function(t){t.stop()})}catch(e){}
  stream=null;if(ac){try{ac.close()}catch(e){}ac=null;an=null;anBuf=null;anBuf8=null}
 }
 var p=stream?Promise.resolve(stream):navigator.mediaDevices.getUserMedia({audio:{echoCancellation:true,noiseSuppression:true,autoGainControl:true,channelCount:1}}).then(function(s){stream=s;return s});
 p.then(function(s){
  if(listening||busy||speaking){starting=false;return} // l'état a bougé pendant l'attente micro
  if(!ac){ac=new (window.AudioContext||window.webkitAudioContext)();an=ac.createAnalyser();an.fftSize=1024;ac.createMediaStreamSource(s).connect(an)}
  if(ac.state==='suspended')ac.resume();
  var chunks=[],sendIt=true,hadSpeech=false,speechTicks=0,silenceMs=0,t0=Date.now(),floor=0.01;
  rec=new MediaRecorder(s,mime?{mimeType:mime,audioBitsPerSecond:48000}:undefined);
  rec.ondataavailable=function(e){if(e.data&&e.data.size)chunks.push(e.data)};
  rec.onerror=function(){sendIt=false;try{rec.stop()}catch(e){}};
  rec.onstop=function(){
   listening=false;mic.classList.remove('listening');mic.style.boxShadow='';if(vadT){clearInterval(vadT);vadT=null}
   var blob=new Blob(chunks,{type:rec.mimeType||mime||'audio/webm'});
   if(sendIt&&hadSpeech&&blob.size>2500)transcribe(blob);
   else{if(handsEl.checked&&!busy&&!speaking){setState('prêt — parle');setTimeout(startListen,300)}else setState('rien entendu — appuie et parle')}
  };
  rec.start(250);
  listening=true;starting=false;mic.classList.add('listening');setState('🎙 je t\\'écoute…');
  vadT=setInterval(function(){
   if(!listening)return;
   var rms=rmsNow();
   if(rms<floor*1.5)floor=Math.min(0.05,Math.max(0.003,0.95*floor+0.05*rms));
   var startThr=Math.max(floor*3.5,0.012),stopThr=Math.max(floor*2.2,0.008);
   var glow=Math.min(28,Math.round(rms*260));
   mic.style.boxShadow=glow>3?'0 0 0 '+glow+'px rgba(224,69,94,.14)':'';
   if(!hadSpeech){
    if(rms>startThr){speechTicks++;if(speechTicks>=2){hadSpeech=true;silenceMs=0;setState('🎙 je t\\'écoute… (parle, je coupe au silence)')}}
    else{speechTicks=0;if(Date.now()-t0>12000){sendIt=false;try{rec.stop()}catch(e){}}}
   }else{
    if(rms<stopThr){silenceMs+=60;if(silenceMs>=800){try{rec.stop()}catch(e){}}}
    else silenceMs=0;
    if(Date.now()-t0>60000){try{rec.stop()}catch(e){}}
   }
  },60);
 }).catch(function(e){starting=false;setState('micro refusé ou indispo : '+e.message)});
}
function stopListenNow(){if(rec&&listening){try{rec.stop()}catch(e){}}}
function transcribe(blob){
 setState('✍️ transcription…');mic.classList.add('busy');
 fetch(base+'/stt',{method:'POST',headers:hdrs({'content-type':blob.type||'application/octet-stream'}),body:blob})
 .then(function(r){if(!r.ok)throw new Error('stt '+r.status);return r.json()})
 .then(function(j){mic.classList.remove('busy');var t=(j.text||'').trim();
  if(t)ask(t);
  else{setState('rien compris — réessaie');if(handsEl.checked&&!busy)setTimeout(startListen,400)}})
 .catch(function(e){mic.classList.remove('busy');add('sys','⚠ reco vocale : '+e.message);setState('erreur STT — réessaie');if(handsEl.checked&&!busy)setTimeout(startListen,1500)});
}
mic.onclick=function(){
 ensureAudio();warm();
 if(listening){stopListenNow();return}
 if(busy)return;
 if(speaking||playing)stopAudio();
 startListen();
};
sendBtn.onclick=function(){ensureAudio();var t=txt.value.trim();if(t){txt.value='';ask(t)}};
txt.addEventListener('keydown',function(e){if(e.key==='Enter')sendBtn.onclick()});
setState('prêt — appuie pour parler');
</script></body></html>`;

// ---- server -----------------------------------------------------------------
const server = http.createServer(async (req, res) => {
  res.setHeader('access-control-allow-origin', '*');
  res.setHeader('access-control-allow-headers', 'Authorization, Content-Type, X-Voice-Token');
  res.setHeader('access-control-allow-methods', 'GET, POST, OPTIONS');
  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

  const u = new URL(req.url, `http://${req.headers.host}`);
  if (u.pathname === '/health' || u.pathname === '/api/health') {
    return send(res, 200, {
      ok: true, brain: BRAIN === 'claude' ? 'claude-cli' : BRAIN,
      model: EFFECTIVE_MODEL,
      effort: BRAIN === 'claude' ? EFFORT : undefined,
      warm: BRAIN === 'claude' ? WARM : undefined, secondBrain: SB,
      brainConfigured: !brainReady(),
      stt: RUNPOD_KEY && STT_EP ? 'runpod' : 'off',
      tts: RUNPOD_KEY && TTS_EP ? 'runpod' : (LOCAL_TTS_URL ? 'local' : 'off'),
    });
  }
  if (u.pathname === '/v1/models' && req.method === 'GET') {
    return send(res, 200, { object: 'list', data: [{ id: EFFECTIVE_MODEL, object: 'model', owned_by: 'safedesk-voice' }] });
  }
  if ((u.pathname === '/voice' || u.pathname === '/voice/') && req.method === 'GET') {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' });
    res.end(VOICE_HTML); return;
  }
  // ---- STT : blob micro (webm/mp4/wav) → faster-whisper RunPod → texte ----
  if (u.pathname === '/voice/stt' && req.method === 'POST') {
    if (!bearerOk(req)) return send(res, 401, { error: 'unauthorized' });
    if (!RUNPOD_KEY || !STT_EP) return send(res, 500, { error: 'stt_not_configured (RUNPOD_API_KEY / RUNPOD_STT_ENDPOINT_ID)' });
    let audio;
    try { audio = await readBodyBuffer(req); } catch (e) { return send(res, 413, { error: String(e.message || e) }); }
    if (!audio || audio.length < 200) return send(res, 400, { error: 'empty_audio' });
    const t0 = Date.now();
    try {
      const out = await runpodRun(STT_EP, {
        audio_base64: audio.toString('base64'),
        model: STT_MODEL, language: STT_LANG, transcription: 'plain_text',
        enable_vad: true, initial_prompt: STT_PROMPT,
      }, STT_TIMEOUT);
      return send(res, 200, { text: String(out?.transcription || '').trim(), detected_language: out?.detected_language, ms: Date.now() - t0 });
    } catch (e) { return send(res, 502, { error: 'stt', detail: String(e.message || e) }); }
  }
  // ---- TTS : texte → Kyutai 1.6B RunPod → WAV (fallback pocket-tts local) ----
  if (u.pathname === '/voice/tts' && req.method === 'POST') {
    if (!bearerOk(req)) return send(res, 401, { error: 'unauthorized' });
    const raw = await readBody(req);
    let text = '';
    try { text = String((JSON.parse(raw || '{}').text) || ''); } catch {}
    if (!text.trim()) return send(res, 400, { error: 'empty' });
    if (RUNPOD_KEY && TTS_EP) {
      try {
        const out = await runpodRun(TTS_EP, { text, voice: RP_TTS_VOICE }, TTS_TIMEOUT);
        if (out?.error) throw new Error(String(out.error).slice(0, 300));
        if (!out?.audio_base64) throw new Error('no audio_base64 in worker output');
        const wav = Buffer.from(out.audio_base64, 'base64');
        res.writeHead(200, { 'content-type': 'audio/wav', 'cache-control': 'no-store', 'x-tts-backend': 'runpod' });
        res.end(wav); return;
      } catch (e) {
        console.error('[tts] runpod failed:', String(e.message || e).slice(0, 300), LOCAL_TTS_URL ? '— falling back to local pocket-tts' : '');
        if (!LOCAL_TTS_URL) return send(res, 502, { error: 'tts', detail: String(e.message || e) });
      }
    }
    if (!LOCAL_TTS_URL) return send(res, 500, { error: 'tts_not_configured' });
    try {
      const form = new FormData();
      form.append('text', text);
      form.append('voice_url', LOCAL_TTS_VOICE);
      const tr = await fetch(`${LOCAL_TTS_URL}/tts`, { method: 'POST', body: form });
      if (!tr.ok) { const t = await tr.text(); return send(res, 502, { error: 'tts', status: tr.status, detail: t.slice(0, 300) }); }
      res.writeHead(200, { 'content-type': 'audio/wav', 'cache-control': 'no-store', 'x-tts-backend': 'local' });
      const reader = tr.body.getReader();
      for (;;) { const { done, value } = await reader.read(); if (done) break; res.write(Buffer.from(value)); }
      res.end();
    } catch (e) {
      // Si le stream local casse APRÈS writeHead, un send() relancerait
      // ERR_HTTP_HEADERS_SENT (crash process) → on coupe la connexion.
      if (res.headersSent) { try { res.destroy(); } catch {} ; return; }
      return send(res, 502, { error: 'tts', detail: String(e.message || e) });
    }
    return;
  }
  // ---- préchauffage : job minuscule sur chaque endpoint, fire-and-forget ----
  if (u.pathname === '/voice/warm' && req.method === 'POST') {
    if (!bearerOk(req)) return send(res, 401, { error: 'unauthorized' });
    const now = Date.now();
    if (now - lastWarm < 30000) return send(res, 200, { ok: true, throttled: true }); // anti-spam
    lastWarm = now;
    try {
      if (RUNPOD_KEY && STT_EP) {
        fetch(`https://api.runpod.ai/v2/${STT_EP}/run`, {
          method: 'POST', headers: rpHeaders(),
          body: JSON.stringify({ input: { audio_base64: silenceWavB64(), model: STT_MODEL, language: STT_LANG, transcription: 'plain_text' } }),
        }).catch(() => {});
      }
      if (RUNPOD_KEY && TTS_EP) {
        fetch(`https://api.runpod.ai/v2/${TTS_EP}/run`, {
          method: 'POST', headers: rpHeaders(),
          body: JSON.stringify({ input: { text: 'Ok.', voice: RP_TTS_VOICE } }),
        }).catch(() => {});
      }
      // Cerveau openai serverless : un mini-tour (1 token, hors historique)
      // réveille le worker vLLM pendant que la personne lit l'écran.
      if (BRAIN === 'openai' && OAI_OK) {
        fetch(`${OAI_BASE}/chat/completions`, {
          method: 'POST',
          headers: { 'content-type': 'application/json', ...(OAI_KEY ? { authorization: `Bearer ${OAI_KEY}` } : {}) },
          body: JSON.stringify({ model: OAI_MODEL, max_tokens: 1, messages: [{ role: 'user', content: 'Ok' }] }),
          signal: AbortSignal.timeout(TIMEOUT_MS),
        }).catch(() => {});
      }
    } catch {}
    return send(res, 200, { ok: true, warming: { stt: !!(RUNPOD_KEY && STT_EP), tts: !!(RUNPOD_KEY && TTS_EP), llm: BRAIN === 'openai' && OAI_OK } });
  }
  // ---- côté AGENT du relay local (HTTP) -------------------------------------
  // Pour un agent CO-LOCALISÉ avec le shim (même transport fichiers que
  // mcp-voice.mjs). En transport DISTANT (VOICE_RELAY_URL posé), les tours
  // partent au hub second-brain : ces routes répondent 409 pour ne pas laisser
  // un agent local long-poller un dossier qui ne se remplira jamais.
  if (u.pathname === '/voice/agent/wait' && (req.method === 'GET' || req.method === 'POST')) {
    if (!bearerOk(req)) return send(res, 401, { error: 'unauthorized' });
    if (BRAIN !== 'relay') return send(res, 409, { error: `VOICE_BRAIN=${BRAIN} — le shim ne route pas les tours vers un agent externe` });
    if (RELAY_URL) return send(res, 409, { error: `transport relay DISTANT actif (${RELAY_URL}) — utilise les outils MCP voice_wait/voice_answer du hub` });
    const cap = Math.min(Math.max(1, Number(u.searchParams.get('timeout_s') || 25)), 50) * 1000;
    const deadline = Date.now() + cap;
    fs.mkdirSync(RELAY_DIR, { recursive: true });
    for (;;) {
      let names = [];
      try { names = fs.readdirSync(RELAY_DIR).filter((n) => n.startsWith('q-') && n.endsWith('.json')).sort(); } catch {}
      for (const n of names) {
        try {
          const q = JSON.parse(fs.readFileSync(`${RELAY_DIR}/${n}`, 'utf8'));
          if (q?.id && q?.text) return send(res, 200, { id: q.id, text: q.text, ts: q.ts });
        } catch { /* fichier en cours d'écriture → tour suivant */ }
      }
      if (Date.now() > deadline) return send(res, 200, { waiting: true });
      await new Promise((s) => setTimeout(s, 250));
    }
  }
  if (u.pathname === '/voice/agent/answer' && req.method === 'POST') {
    if (!bearerOk(req)) return send(res, 401, { error: 'unauthorized' });
    if (RELAY_URL) return send(res, 409, { error: `transport relay DISTANT actif (${RELAY_URL}) — utilise les outils MCP voice_wait/voice_answer du hub` });
    const raw = await readBody(req);
    let p; try { p = JSON.parse(raw || '{}'); } catch { return send(res, 400, { error: 'bad_json' }); }
    const id = String(p.id || '').replace(/[^0-9a-zA-Z_-]/g, '');
    const text = String(p.text || '').trim();
    if (!id || !text) return send(res, 400, { error: 'id et text requis' });
    if (!fs.existsSync(`${RELAY_DIR}/q-${id}.json`)) {
      return send(res, 404, { error: `question ${id} inconnue ou expirée — attends la suivante via /voice/agent/wait` });
    }
    // write + rename = atomique (askRelay ne lira jamais un fichier partiel)
    const tmp = `${RELAY_DIR}/.a-${id}.tmp`;
    try { fs.writeFileSync(tmp, text + '\n'); fs.renameSync(tmp, `${RELAY_DIR}/a-${id}.txt`); }
    catch (e) { return send(res, 500, { error: String(e.message || e) }); }
    return send(res, 200, { ok: true, spoken: text.length });
  }
  // /voice/chat = alias sous-chemin (page derrière le nginx SafeDesk) ;
  // /v1/chat/completions = façade OpenAI-compat pour les clients API.
  if ((u.pathname === '/v1/chat/completions' || u.pathname === '/voice/chat') && req.method === 'POST') {
    if (!bearerOk(req)) return send(res, 401, { error: 'unauthorized' });
    const notReady = brainReady();
    if (notReady) return send(res, 500, { error: notReady });
    const raw = await readBody(req);
    let payload; try { payload = JSON.parse(raw || '{}'); } catch { return send(res, 400, { error: 'bad_json' }); }
    const id = 'chatcmpl-voice';
    const userText = lastUserText(payload.messages);

    // Mode NON-STREAM (stream:false ou absent) : réponse JSON OpenAI classique.
    if (payload.stream !== true) {
      try {
        const full = await askBrain(userText, () => {});
        return send(res, 200, {
          id, object: 'chat.completion', created: 0, model: EFFECTIVE_MODEL,
          choices: [{ index: 0, message: { role: 'assistant', content: full }, finish_reason: 'stop' }],
          usage: { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 },
        });
      } catch (e) { return send(res, 502, { error: 'brain', detail: String(e.message || e).slice(0, 300) }); }
    }

    // Mode STREAM (SSE) : utilisé par la page vocale (envoie stream:true).
    res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-cache', connection: 'keep-alive', 'x-accel-buffering': 'no' });
    // Heartbeat : le cerveau relay/agentique peut rester muet >60s — sans un
    // octet de temps en temps, un proxy intermédiaire coupe le flux et la page
    // termine le tour en silence. Un commentaire SSE (`: ping`) est ignoré par
    // le parseur de la page (elle ne lit que les lignes `data:`).
    const hb = setInterval(() => { try { res.write(': ping\n\n'); } catch {} }, 15000);
    try {
      await askBrain(userText, (t) => res.write(sseChunk(id, t)));
    } catch (e) {
      // Les cerveaux claude ne rejettent jamais ; openai/relay peuvent (réseau,
      // 4xx/5xx, timeout). Le statut HTTP est déjà parti → l'erreur part comme
      // texte, lue à voix haute.
      res.write(sseChunk(id, `Désolé, le cerveau ne répond pas : ${String(e.message || e).slice(0, 200)}`));
      console.error('[brain] stream', String(e.message || e).slice(0, 300));
    } finally { clearInterval(hb); }
    res.write(sseChunk(id, '', 'stop'));
    res.write('data: [DONE]\n\n');
    res.end();
    return;
  }
  send(res, 404, { error: 'not_found' });
});

// Filet de sécurité : ce process héberge la session claude chaude — une
// promesse orpheline (fetch RunPod, stream cassé) ne doit pas tuer le shim.
process.on('unhandledRejection', (e) => console.error('[shim] unhandledRejection:', String(e?.message || e).slice(0, 300)));

server.listen(PORT, () => {
  const brainDesc = BRAIN === 'openai'
    ? `openai(${OAI_MODEL || '?'} @ ${OAI_BASE ? new URL(OAI_BASE).host : '?'})`
    : BRAIN === 'relay' ? `relay(${RELAY_URL ? 'hub ' + RELAY_URL : RELAY_DIR})`
    : `claude(${MODEL}/${EFFORT}) warm=${WARM}`;
  console.log(`brain-shim :${PORT}  brain=${brainDesc}  ready=${brainReady() || 'OK'}  second-brain=${SB ? 'on' + (PLANE_PROJECT ? '→' + PLANE_PROJECT : '') : 'off'}  stt=${RUNPOD_KEY && STT_EP ? 'runpod' : 'off'}  tts=${RUNPOD_KEY && TTS_EP ? 'runpod' : (LOCAL_TTS_URL ? 'local' : 'off')}`);
});
