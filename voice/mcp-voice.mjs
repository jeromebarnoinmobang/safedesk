#!/usr/bin/env node
// =============================================================================
// mcp-voice.mjs — serveur MCP (stdio) qui donne des OREILLES et une VOIX à un
// agent : le pont vers le cerveau `relay` de brain-shim.mjs (VOICE_BRAIN=relay).
//
// La page /voice/ fait : micro → STT → q-<id>.json dans VOICE_RELAY_DIR, puis
// attend a-<id>.txt → TTS → haut-parleur. Cet MCP expose ce protocole :
//   voice_wait   : attendre la prochaine phrase de la personne ({id, text})
//   voice_answer : répondre (le texte part en synthèse vocale)
//
// Zéro dépendance : JSON-RPC 2.0 sur stdin/stdout, framé par lignes (un
// message JSON par ligne — le transport stdio de MCP).
//
// Enregistrement (scope user) :
//   claude mcp add voice -- node /chemin/vers/voice/mcp-voice.mjs
// (ou via le .mcp.json à la racine du repo safedesk.)
// =============================================================================
import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';

const RELAY_DIR = process.env.VOICE_RELAY_DIR || '/tmp/safedesk-voice-relay';
// Borne d'attente PAR APPEL de voice_wait (l'agent rappelle l'outil pour
// continuer d'écouter) — sous les timeouts d'outils MCP usuels.
const WAIT_CAP_MS = Number(process.env.VOICE_WAIT_CAP_MS || 50000);

const TOOLS = [
  {
    name: 'voice_wait',
    description: "Attend la prochaine phrase dite par la personne sur la page vocale SafeDesk (déjà transcrite). Retourne {id, text}, ou {waiting: true} si rien après ~50s — rappelle l'outil pour continuer d'écouter. Réponds ensuite avec voice_answer et l'id reçu.",
    inputSchema: {
      type: 'object',
      properties: { timeout_seconds: { type: 'number', description: 'Attente max de cet appel (défaut 50, plafonné à 50)' } },
    },
  },
  {
    name: 'voice_answer',
    description: "Répond à voix haute à une phrase reçue via voice_wait. Le texte est lu par la synthèse vocale : phrases courtes, ton naturel, pas de markdown ni de listes. id = celui retourné par voice_wait.",
    inputSchema: {
      type: 'object',
      properties: {
        id: { type: 'string', description: 'id de la question (retourné par voice_wait)' },
        text: { type: 'string', description: 'La réponse, telle qu\'elle sera lue à voix haute' },
      },
      required: ['id', 'text'],
    },
  },
];

function pendingQuestions() {
  let names;
  try { names = fs.readdirSync(RELAY_DIR); } catch { return []; }
  return names.filter((n) => n.startsWith('q-') && n.endsWith('.json')).sort();
}
function readQuestion(name) {
  try { return JSON.parse(fs.readFileSync(path.join(RELAY_DIR, name), 'utf8')); }
  catch { return null; }
}

async function toolWait(args) {
  const cap = Math.min(Math.max(1, Number(args?.timeout_seconds || 50)), WAIT_CAP_MS / 1000) * 1000;
  const deadline = Date.now() + cap;
  for (;;) {
    for (const n of pendingQuestions()) {
      const q = readQuestion(n);
      if (q?.id && q?.text) return { id: q.id, text: q.text };
    }
    if (Date.now() > deadline) return { waiting: true, hint: "rien entendu — rappelle voice_wait pour continuer d'écouter" };
    await new Promise((s) => setTimeout(s, 250));
  }
}
function toolAnswer(args) {
  const id = String(args?.id || '').replace(/[^0-9a-zA-Z_-]/g, '');
  const text = String(args?.text || '').trim();
  if (!id || !text) throw new Error('id et text requis');
  if (!fs.existsSync(path.join(RELAY_DIR, `q-${id}.json`))) {
    throw new Error(`question ${id} inconnue ou expirée (le shim a un timeout par tour) — attends la suivante avec voice_wait`);
  }
  fs.mkdirSync(RELAY_DIR, { recursive: true });
  // write + rename = atomique : le shim ne lira jamais un fichier à moitié écrit
  const tmp = path.join(RELAY_DIR, `.a-${id}.tmp`);
  fs.writeFileSync(tmp, text + '\n');
  fs.renameSync(tmp, path.join(RELAY_DIR, `a-${id}.txt`));
  return { ok: true, spoken: text.length };
}

// ---- JSON-RPC / MCP ----------------------------------------------------------
const out = (msg) => process.stdout.write(JSON.stringify(msg) + '\n');
const reply = (id, result) => out({ jsonrpc: '2.0', id, result });
const replyErr = (id, code, message) => out({ jsonrpc: '2.0', id, error: { code, message } });

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
rl.on('line', async (line) => {
  if (!line.trim()) return;
  let m; try { m = JSON.parse(line); } catch { return; }
  const { id, method, params } = m;
  try {
    if (method === 'initialize') {
      return reply(id, {
        protocolVersion: params?.protocolVersion || '2025-06-18',
        capabilities: { tools: {} },
        serverInfo: { name: 'safedesk-voice', version: '1.0.0' },
      });
    }
    if (method === 'notifications/initialized' || String(method || '').startsWith('notifications/')) return; // notifications : pas de réponse
    if (method === 'tools/list') return reply(id, { tools: TOOLS });
    if (method === 'tools/call') {
      const name = params?.name, args = params?.arguments || {};
      let res;
      if (name === 'voice_wait') res = await toolWait(args);
      else if (name === 'voice_answer') res = toolAnswer(args);
      else return replyErr(id, -32602, `outil inconnu: ${name}`);
      return reply(id, { content: [{ type: 'text', text: JSON.stringify(res) }] });
    }
    if (method === 'ping') return reply(id, {});
    if (id !== undefined) return replyErr(id, -32601, `méthode inconnue: ${method}`);
  } catch (e) {
    if (id !== undefined) return reply(id, { content: [{ type: 'text', text: `Erreur: ${String(e.message || e)}` }], isError: true });
  }
});
rl.on('close', () => process.exit(0));
