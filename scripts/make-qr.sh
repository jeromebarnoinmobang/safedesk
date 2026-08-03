#!/usr/bin/env bash
# Genere les QR codes SafeDesk. Tout est parametrable (arguments > variables d env > .env).
#
#   make-qr.sh --install [--repo owner/nom] [--out fichier.png]
#       QR vers le dernier APK publie. Repo deduit du remote git si absent.
#
#   make-qr.sh [--env fichier] [--name nom] [--url https://...|http://ip-privee] [--domain d]
#              [--user u] [--pass p] [--fp empreinte|--pin] [--out fichier.png]
#       --pin : recupere et epingle l empreinte SHA-256 du certificat presente par
#               le serveur (pour un certificat auto-signe, sans nom de domaine).
#       http:// n est accepte que vers une adresse privee/VPN (tunnel deja chiffre).
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
FP="${SAFEDESK_FP:-}"; PIN=0

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
    --fp)      FP="$2"; shift ;;
    --pin)     PIN=1 ;;
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
is_private_host() {
  case "$1" in
    localhost) return 0 ;;
    10.*|127.*|192.168.*|169.254.*) return 0 ;;
    172.1[6-9].*|172.2[0-9].*|172.3[0-1].*) return 0 ;;
    100.6[4-9].*|100.[7-9][0-9].*|100.1[0-1][0-9].*|100.12[0-7].*) return 0 ;;
    *) return 1 ;;
  esac
}
hostport=${URL#*://}; hostport=${hostport%%/*}
host=${hostport%%:*}; port=${hostport#*:}; [ "$port" = "$host" ] && port=""
case "$URL" in
  https://*) ;;
  http://*)
    is_private_host "$host" || {
      echo "http:// refuse vers $host : uniquement une adresse privee/VPN (le tunnel chiffre deja)" >&2
      exit 1
    } ;;
  *) echo "url invalide ($URL)" >&2; exit 1 ;;
esac
if [ "$PIN" = "1" ]; then
  command -v openssl >/dev/null || { echo "openssl requis pour --pin" >&2; exit 1; }
  FP=$(openssl s_client -connect "$host:${port:-443}" -servername "$host" </dev/null 2>/dev/null \
       | openssl x509 -outform DER 2>/dev/null | openssl dgst -sha256 | grep -o "[0-9a-f]\{64\}")
  [ -n "$FP" ] || { echo "impossible de recuperer le certificat de $host" >&2; exit 1; }
  echo "empreinte epinglee : $FP"
fi
FP=$(printf "%s" "$FP" | tr -d ":" | tr "A-F" "a-f")

if [ -n "$FP" ]; then
  JSON=$(printf '{"v":1,"name":"%s","url":"%s","user":"%s","pass":"%s","fp":"%s"}' "$NAME" "$URL" "$USR" "$PASS" "$FP")
else
  JSON=$(printf '{"v":1,"name":"%s","url":"%s","user":"%s","pass":"%s"}' "$NAME" "$URL" "$USR" "$PASS")
fi
DATA=$(printf "%s" "$JSON" | base64 -w0 | tr "+/" "-_" | tr -d "=")
OUT="${OUT:-qr-connect.png}"
qrencode -s 8 -m 2 -o "$OUT" "safedesk://connect?data=$DATA"
echo "$OUT -> $URL (user: $USR)"
echo "Ce QR contient les identifiants : a montrer uniquement a la personne concernee."