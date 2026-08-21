#!/usr/bin/env bash
# Mise a jour automatique du depot, lancee par le minuteur systemd.
#
# CE QU IL FAIT, ET SURTOUT CE QU IL NE FAIT PAS. Il tire le depot. Il ne redemarre
# JAMAIS le bureau. Jerome travaille dedans : le couper sans prevenir remplacerait
# un desagrement par une perte de travail, et une mise a jour n a jamais assez de
# valeur pour ca. La nouvelle version prend effet au prochain « make local », qui
# tire deja lui-meme avant de lancer.
#
# Quand une mise a jour est arrivee, on pose un marqueur : le demarrage suivant
# saura le dire, plutot que de laisser Jerome deviner qu il tourne sur du vieux
# code. Constate le 21/08/2026 : le clone de la station avait QUINZE commits de
# retard, dont le correctif qui lui aurait rendu sa camera.
set -euo pipefail
cd "$(dirname "$0")/.."

MARQUEUR=${SAFEDESK_MARQUEUR:-/var/lib/safedesk/maj-en-attente}

avant=$(git rev-parse HEAD)

# Memes garde-fous qu au demarrage : jamais de demande d identifiants (le distant
# est en HTTPS, une invite bloquerait le minuteur indefiniment), jamais de fusion a
# resoudre sans personne devant, et un reseau qui pend ne doit pas rester accroche.
if ! GIT_TERMINAL_PROMPT=0 timeout 120 git pull --ff-only --quiet 2>/dev/null; then
  echo "maj : impossible de tirer (reseau, identifiants ou divergence) — on garde ${avant:0:7}"
  exit 0   # ce n'est pas un incident : la machine reste utilisable
fi

apres=$(git rev-parse HEAD)
if [ "$avant" = "$apres" ]; then
  echo "maj : deja a jour (${apres:0:7})"
  exit 0
fi

nb=$(git rev-list --count "$avant..$apres")
echo "maj : $nb commit(s) recuperes, ${avant:0:7} -> ${apres:0:7}"
git --no-pager log --oneline "$avant..$apres" | head -10

mkdir -p "$(dirname "$MARQUEUR")"
printf '%s commit(s) en attente (%s -> %s), pris en compte au prochain « make local »\n' \
  "$nb" "${avant:0:7}" "${apres:0:7}" > "$MARQUEUR"
