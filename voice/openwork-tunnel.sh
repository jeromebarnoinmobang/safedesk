#!/bin/bash
# openwork-tunnel.sh — expose OpenWork au téléphone via le VPS (openwork.mobang.fr).
# Même principe que le tunnel du bureau (safedesk-home) : tunnel SSH INVERSE
# sortant — rien d'ouvert sur la box. Deux ports remontent au VPS :
#   14980 -> front OpenWork local (14880)      [openwork.mobang.fr]
#   14977 -> serveur openwork local (14877)    [openwork-api.mobang.fr]
# Traefik les joint via la passerelle docker (172.18.0.1), routes déclarées dans
# /opt/mobang/traefik/dynamic/openwork.yml.
# Usage : ./openwork-tunnel.sh          (boucle supervisée, relance auto)
#         ./openwork-tunnel.sh stop
set -u
PIDF=/tmp/openwork-tunnel.pid
if [ "${1:-}" = "stop" ]; then
  [ -f $PIDF ] && kill "$(cat $PIDF)" 2>/dev/null && rm -f $PIDF && echo "tunnel arrêté" && exit 0
  echo "pas de tunnel actif"; exit 0
fi
echo $$ > $PIDF
echo "tunnel OpenWork -> mobang-prod (Ctrl-C ou './openwork-tunnel.sh stop' pour arrêter)"
while true; do
  ssh -o BatchMode=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
      -o ExitOnForwardFailure=yes -N \
      -R '0.0.0.0:14980:127.0.0.1:14880' \
      -R '0.0.0.0:14977:127.0.0.1:14877' \
      mobang-prod
  echo "[openwork-tunnel] coupé — reconnexion dans 5s"
  sleep 5
done
