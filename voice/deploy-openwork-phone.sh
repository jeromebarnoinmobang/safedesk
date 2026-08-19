#!/bin/bash
# deploy-openwork-phone.sh — UN geste : OpenWork accessible du téléphone.
#   https://openwork.mobang.fr  (login = le même que ton bureau SafeDesk)
# Fait : 1) route traefik sur le VPS (auth Basic, hash seulement — le mot de
# passe ne quitte pas cette machine) ; 2) démarre le tunnel SSH inverse
# supervisé (openwork-tunnel.sh). Relançable sans risque (idempotent).
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

U=$(cat /run/s6/container_environment/CUSTOM_USER)
P=$(cat /run/s6/container_environment/PASSWORD)
HASH=$(printf '%s' "$P" | openssl passwd -apr1 -stdin)

echo "1/3 — écriture de la route traefik sur mobang-prod…"
ssh -o BatchMode=yes mobang-prod "cat > /opt/mobang/traefik/dynamic/openwork.yml" <<EOF
# OpenWork — app web du poste de travail IA du PC fixe, servie au téléphone.
# Même mécanique que safedesk-home.yml : tunnels SSH inverses remontés par le
# fixe (openwork-tunnel.sh) ; traefik les joint via la passerelle docker.
http:
  middlewares:
    openwork-auth:
      basicAuth:
        users:
          - "$U:$HASH"
  routers:
    openwork-front:
      rule: "Host(\`openwork.mobang.fr\`)"
      entryPoints: [websecure]
      middlewares: [security-headers@file, openwork-auth@file]
      service: openwork-front
      tls: { certResolver: letsencrypt }
    openwork-api:
      # PAS de basicauth ici : le front envoie deja Authorization: Bearer <jeton
      # fort> et le serveur openwork refuse sans lui — un basicauth collisionnerait.
      rule: "Host(\`openwork-api.mobang.fr\`)"
      entryPoints: [websecure]
      middlewares: [security-headers@file]
      service: openwork-api
      tls: { certResolver: letsencrypt }
  services:
    openwork-front:
      loadBalancer: { passHostHeader: true, servers: [{ url: "http://172.18.0.1:14980" }] }
    openwork-api:
      loadBalancer: { passHostHeader: true, servers: [{ url: "http://172.18.0.1:14977" }] }
EOF
echo "   route écrite (traefik la recharge tout seul)."

echo "2/3 — tunnel SSH inverse (supervisé)…"
"$DIR/openwork-tunnel.sh" stop >/dev/null 2>&1 || true
setsid "$DIR/openwork-tunnel.sh" > /tmp/openwork-tunnel.log 2>&1 &
sleep 4

echo "3/3 — vérification de bout en bout…"
sleep 3
code=$(curl -s -o /dev/null -w '%{http_code}' -m 15 https://openwork.mobang.fr/ || true)
echo "   https://openwork.mobang.fr sans login -> $code (401 attendu = auth active)"
code=$(curl -s -o /dev/null -w '%{http_code}' -m 15 -u "$U:$P" https://openwork.mobang.fr/ || true)
echo "   avec ton login -> $code (200 attendu)"
echo
echo "✅ Sur ton téléphone : ouvre https://openwork.mobang.fr (login du bureau),"
echo "   puis « Ajouter à l'écran d'accueil » pour en faire une vraie appli."
