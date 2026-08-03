#!/usr/bin/env bash
# Genere les QR codes SafeDesk. Tout est parametrable (arguments > variables d env > .env).
#
#   make-qr.sh --install [--repo owner/nom] [--out fichier.png]
#       QR vers le dernier APK publie. Repo deduit du remote git si absent.
#
#   make-qr.sh [--env fichier] [--name nom] [--url https://...] [--domain d]
#              [--user u] [--pass p] [--out fichier.png]
#       QR de configuration safedesk://connect?data=<base64url(json)>.
#       Valeurs manquantes lues dans le fichier env (defaut: .env) :
#       DESKTOP_DOMAIN / DESKTOP_USER / DESKTOP_PASSWORD / SAFEDESK_NAME.
#
# Necessite : qrencode. Variables d env acceptees : SAFEDESK_REPO, SAFEDESK_NAME,
# SAFEDESK_URL, SAFEDESK_USER, SAFEDESK_PASS.
set -euo pipefail
cd "$(dirname "$0")/.."

MODE=config; ENVFILE=.env; OUT=""; REPO="${SAFEDESK_REPO:-}"
NAME="${SAFEDESK_NAME:-}"; URL="${SAFEDESK_URL:-}"; DOMAIN=""; USR="${SAFEDESK_USER:-}"; PASS="${SAFEDESK_PASS:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --install) MODE=install ;;
    --repo)    REPO="$2"; shift ;;
    --env)     ENVFILE="$2"; shift ;;
    --name)    NAME="$2"; shift ;;
    --url)     URL="$2"; shift ;;
    --domain)  DOMAIN="$2"; shift ;;
    --user)    USR="$2"; shift ;;
    --pass)    PASS="$2"; shift ;;
    --out)     OUT="$2"; shift ;;
    -h|--help) grep "^#" "$0" | sed "s/^# \{0,1\}//"; exit 0 ;;
    *) echo "option inconnue: $1 (voir --help)" >&2; exit 2 ;;
  esac
  shift
done

command -v qrencode >/dev/null || { echo "qrencode manquant (apt install qrencode)" >&2; exit 1; }

if [ "$MODE" = "install" ]; then
  if [ -z "$REPO" ]; then
    origin=$(git config --get remote.origin.url 2>/dev/null || true)
    REPO=$(printf "%s" "$origin" | sed -E "s#(git@[^:]+:|https?://[^/]+/)##; s#\.git\$##")
  fi
  [ -n "$REPO" ] || { echo "repo introuvable : --repo owner/nom ou SAFEDESK_REPO" >&2; exit 1; }
  APK=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
        | grep browser_download_url | grep -o "https://[^\"]*\.apk" | head -1)
  [ -n "$APK" ] || { echo "aucun APK dans la derniere release de $REPO" >&2; exit 1; }
  OUT="${OUT:-qr-install.png}"
  qrencode -s 8 -m 2 -o "$OUT" "$APK"
  echo "$OUT -> $APK"
  exit 0
fi

get() { [ -f "$ENVFILE" ] && grep -E "^$1=" "$ENVFILE" | tail -1 | cut -d= -f2- || true; }
[ -n "$DOMAIN" ] && URL="https://$DOMAIN"
[ -n "$URL" ]  || { d=$(get DESKTOP_DOMAIN); [ -n "$d" ] && URL="https://$d"; }
[ -n "$USR" ]  || USR=$(get DESKTOP_USER)
[ -n "$PASS" ] || PASS=$(get DESKTOP_PASSWORD)
[ -n "$NAME" ] || NAME=$(get SAFEDESK_NAME)
NAME="${NAME:-SafeDesk}"

[ -n "$URL" ] && [ -n "$USR" ] && [ -n "$PASS" ] || {
  echo "il manque url/user/pass (arguments, variables SAFEDESK_*, ou $ENVFILE)" >&2; exit 1; }
case "$URL" in https://*) ;; *) echo "l url doit etre en https ($URL)" >&2; exit 1 ;; esac

JSON=$(printf '{"v":1,"name":"%s","url":"%s","user":"%s","pass":"%s"}' "$NAME" "$URL" "$USR" "$PASS")
DATA=$(printf "%s" "$JSON" | base64 -w0 | tr "+/" "-_" | tr -d "=")
OUT="${OUT:-qr-connect.png}"
qrencode -s 8 -m 2 -o "$OUT" "safedesk://connect?data=$DATA"
echo "$OUT -> $URL (user: $USR)"
echo "Ce QR contient les identifiants : a montrer uniquement a la personne concernee."