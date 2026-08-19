#!/usr/bin/env node
// local-tts.mjs — voix de secours LOCALE (pico2wave, français) pour le brain-shim.
// Contrat compatible avec le fallback LOCAL_TTS_URL du shim : POST /tts (multipart
// form `text`, ou JSON {text}, ou texte brut) → audio/wav. CPU, hors-ligne, zéro
// dépendance (que du Node natif + le binaire pico2wave). Sert quand l'endpoint
// RunPod Kyutai est indisponible ; remplacer par Kyutai dès qu'il refonctionne.
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import { execFile } from 'node:child_process';

const PORT = Number(process.env.LOCAL_TTS_PORT || 8200);
const LANG = process.env.LOCAL_TTS_LANG || 'fr-FR';

function readBuf(req, max = 2 * 1024 * 1024) {
  return new Promise((resolve, reject) => {
    const c = []; let n = 0;
    req.on('data', (d) => { n += d.length; if (n > max) { reject(new Error('too_large')); req.destroy(); return; } c.push(d); });
    req.on('end', () => resolve(Buffer.concat(c)));
    req.on('error', reject);
  });
}

// Extrait le champ `text` d'un corps : multipart (FormData du shim), JSON, ou brut.
function extractText(buf, ctype) {
  const raw = buf.toString('utf8');
  if (ctype.includes('multipart/form-data')) {
    const m = raw.match(/name="text"\r?\n\r?\n([\s\S]*?)\r?\n--/);
    if (m) return m[1];
  }
  if (ctype.includes('application/json')) {
    try { return String(JSON.parse(raw || '{}').text || ''); } catch { return ''; }
  }
  return raw;
}

// pico2wave n'aime pas le markdown ni certains symboles : on nettoie pour une
// lecture fluide. Cap de sûreté (les réponses vocales sont courtes de toute façon).
function clean(t) {
  return t.replace(/[*_`#>|]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 2000);
}

// Piper (qualité) d'abord, pico2wave (robotique) en ultime secours.
const PIPER_BIN = process.env.PIPER_BIN || `${os.homedir()}/.local/piper/piper/piper`;
const PIPER_MODEL = process.env.PIPER_MODEL || `${os.homedir()}/.local/piper/fr_FR-siwis-medium.onnx`;
const hasPiper = fs.existsSync(PIPER_BIN) && fs.existsSync(PIPER_MODEL);

function synth(text) {
  return new Promise((resolve, reject) => {
    const wav = `${os.tmpdir()}/tts-${process.pid}-${Date.now()}.wav`;
    const done = (err) => {
      if (err) return reject(err);
      fs.readFile(wav, (e, data) => { try { fs.unlinkSync(wav); } catch {} ; e ? reject(e) : resolve(data); });
    };
    if (hasPiper) {
      const p = execFile(PIPER_BIN, ['--model', PIPER_MODEL, '--output_file', wav], (err) => {
        if (!err) return done();
        // piper a échoué → repli pico
        execFile('pico2wave', ['-l', LANG, '-w', wav, text], done);
      });
      p.stdin.end(text);
    } else {
      execFile('pico2wave', ['-l', LANG, '-w', wav, text], done);
    }
  });
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'GET' && (req.url === '/health' || req.url === '/')) {
    res.writeHead(200, { 'content-type': 'application/json' });
    return res.end(JSON.stringify({ ok: true, engine: 'pico2wave', lang: LANG }));
  }
  if (req.method === 'POST' && req.url === '/tts') {
    try {
      const buf = await readBuf(req);
      const text = clean(extractText(buf, req.headers['content-type'] || ''));
      if (!text) { res.writeHead(400, { 'content-type': 'application/json' }); return res.end('{"error":"empty"}'); }
      const wav = await synth(text);
      res.writeHead(200, { 'content-type': 'audio/wav', 'cache-control': 'no-store', 'x-tts-backend': 'pico-local' });
      return res.end(wav);
    } catch (e) {
      res.writeHead(502, { 'content-type': 'application/json' });
      return res.end(JSON.stringify({ error: 'tts', detail: String(e.message || e).slice(0, 200) }));
    }
  }
  res.writeHead(404); res.end();
});
server.listen(PORT, '127.0.0.1', () => console.log(`local-tts :${PORT} (pico2wave ${LANG})`));
