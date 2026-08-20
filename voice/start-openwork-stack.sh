#!/bin/bash
# start-openwork-stack.sh — démarrage IDEMPOTENT de la pile OpenWork complète.
#   1. chaîne dev : fork opencode :14099 + serveur openwork :14877 + front :14880
#      → délégué à workbench-docs/run-chaine-dev.sh (source de vérité, rien de dupliqué ici)
#   2. voix : page discussion :8089 + TTS local :8200
#      → délégué à start-voice-discussion.sh (même dossier)
#   3. publication réseau : si front/serveur n'écoutent que sur 127.0.0.1 (cas du
#      jumeau VPS où traefik doit joindre mobang-desktop:14880/14877 par le réseau
#      docker second-brain), un forwarder node IP-conteneur:PORT → 127.0.0.1:PORT
#      est lancé. Sans effet là où les ports sont déjà joignables.
#
# Fichier SYNCHRONISÉ (Syncthing) : identique sur le fixe et le jumeau VPS.
# Pas d'autostart système : décision Jérôme en attente — lancer ce script à la main.
# Garde-fou : chaque bloc vérifie la santé AVANT d'agir (relançable sans risque).
# Usage : ./start-openwork-stack.sh [stop]
set -u
export PATH="$HOME/.local/bin:$PATH"
DIR="$(cd "$(dirname "$0")" && pwd)"
CHAIN=/config/Projects/workbench/workbench-docs/run-chaine-dev.sh
LOG=/tmp/safedesk-voice; mkdir -p "$LOG"

code() { curl -s -o /dev/null -m 3 -w '%{http_code}' "$1" 2>/dev/null; }
ok()   { [ "$(code "$1")" = "200" ]; }   # 200 attendu (health/front)
up()   { [ "$(code "$1")" != "000" ]; }  # n'importe quelle réponse HTTP = ça écoute

if [ "${1:-}" = "stop" ]; then
  bash "$CHAIN" stop
  bash "$DIR/start-voice-discussion.sh" stop
  # forwarders éventuels (partagent les ports front/serveur)
  fuser -k 14880/tcp 2>/dev/null; fuser -k 14877/tcp 2>/dev/null
  echo "pile OpenWork arrêtée"
  exit 0
fi

# --- 1. chaîne (fork + serveur + front) ---
if ok http://127.0.0.1:14099/global/health && up http://127.0.0.1:14877/ && up http://127.0.0.1:14880/; then
  echo "chaîne : déjà en route (14099/14877/14880) — skip"
else
  bash "$CHAIN" stop >/dev/null 2>&1; sleep 1
  bash "$CHAIN"
fi

# --- 2. voix (page 8089 + TTS 8200) ---
if ok http://127.0.0.1:8089/health; then
  echo "voix : déjà en route (8089) — skip"
else
  bash "$DIR/start-voice-discussion.sh"
fi

# --- 3. publication sur l'IP du conteneur (jumeau : traefik → mobang-desktop:PORT) ---
IP=$(hostname -i 2>/dev/null | awk '{print $1}')
if [ -n "$IP" ] && [ "$IP" != "127.0.0.1" ]; then
  for P in 14880 14877; do
    if up "http://127.0.0.1:$P/" && ! up "http://$IP:$P/"; then
      setsid node -e "
        const net=require('net');
        net.createServer(s=>{const c=net.connect($P,'127.0.0.1');
          s.pipe(c).pipe(s);
          s.on('error',()=>c.destroy());c.on('error',()=>s.destroy());
        }).listen($P,'$IP',()=>console.log('publish $IP:$P -> 127.0.0.1:$P'));
      " > "$LOG/publish-$P.log" 2>&1 &
      for i in 1 2 3 4 5; do up "http://$IP:$P/" && break; sleep 1; done
      up "http://$IP:$P/" && echo "publié : $IP:$P → 127.0.0.1:$P" \
        || echo "ATTENTION : publication du port $P échouée (voir $LOG/publish-$P.log)"
    fi
  done
fi

echo "pile OpenWork prête : front http://127.0.0.1:14880 · voix http://127.0.0.1:8089/voice"
