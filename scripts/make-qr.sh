#!/usr/bin/env bash
# Genere les QR codes SafeDesk.
#   ./scripts/make-qr.sh            -> qr-connect.png (configuration : url + identifiants du .env)
#   ./scripts/make-qr.sh --install  -> qr-install.png (lien de telechargement du dernier APK)
# Necessite : qrencode (apt install qrencode)
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "${1:-}" = "--install" ]; then
  REPO="${SAFEDESK_REPO:-jeromebarnoinmobang/safedesk}"
  URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
        | grep browser_download_url | grep -o 'https://[^"]*\.apk' | head -1)
  [ -n "$URL" ] || { echo "Aucun APK dans la derniere release de $REPO" >&2; exit 1; }
  qrencode -s 8 -m 2 -o qr-install.png "$URL"
  echo "qr-install.png -> $URL"
  exit 0
fi

[ -f .env ] || { echo ".env introuvable" >&2; exit 1; }
get() { grep -E "^$1=" .env | tail -1 | cut -d= -f2-; }
DOMAIN=$(get DESKTOP_DOMAIN); USER=$(get DESKTOP_USER); PASS=$(get DESKTOP_PASSWORD)
NAME=$(get SAFEDESK_NAME); NAME=${NAME:-SafeDesk}
[ -n "$DOMAIN" ] && [ -n "$USER" ] && [ -n "$PASS" ] || { echo "DESKTOP_DOMAIN/USER/PASSWORD requis dans .env" >&2; exit 1; }

JSON=$(printf '{"v":1,"name":"%s","url":"https://%s","user":"%s","pass":"%s"}' "$NAME" "$DOMAIN" "$USER" "$PASS")
DATA=$(printf '%s' "$JSON" | base64 -w0 | tr '+/' '-_' | tr -d '=')
qrencode -s 8 -m 2 -o qr-connect.png "safedesk://connect?data=$DATA"
echo "qr-connect.png -> https://$DOMAIN (user: $USER)"
echo "Ce QR contient les identifiants : le montrer uniquement a la personne concernee."