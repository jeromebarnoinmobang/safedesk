#!/usr/bin/env bash
# Lance le bureau DERRIERE UN REVERSE PROXY (VPS) — pendant de up-local.sh.
#
# POURQUOI CE SCRIPT EXISTE. Le demarrage distant etait une ligne de Makefile et
# une liste de fichiers compose ecrite a la main. Le demarrage local, lui, avait
# son script. Resultat : deux chemins qui divergeaient sans que rien ne le dise —
# c'est exactement ce qui a fait qu'une camera ne survivait pas a un redemarrage
# sur le poste (constate le 21/08/2026). Un chemin par machine, ecrit une fois,
# vaut mieux que deux listes qu'on croit identiques.
#
# CE QUI DIFFERE DU LOCAL, et rien d'autre :
#   - aucun port publie : Traefik expose le bureau en HTTPS (docker-compose.remote.yml) ;
#   - pas de sonde GPU : le VPS n'en a pas, on force le rendu logiciel ;
#   - l'override AV est conserve car c'est ce qui tourne deja, et parce que la
#     camera VIRTUELLE (v4l2loopback, flux page -> ffmpeg) a besoin de /dev quand
#     elle est activee. Sans module charge, il ne fait simplement rien.
set -euo pipefail
cd "$(dirname "$0")/.."

# Mise a jour du depot, jamais au prix du bureau. Memes garde-fous que up-local.sh :
# --ff-only (aucun conflit a resoudre sans personne devant), pas de demande
# d'identifiants (le distant est en HTTPS, une invite bloquerait indefiniment),
# delai borne, et l'echec est annonce sans etre fatal.
if git rev-parse --git-dir >/dev/null 2>&1; then
  printf '[maj] mise a jour du depot... '
  if GIT_TERMINAL_PROMPT=0 timeout 60 git pull --ff-only --quiet 2>/dev/null; then
    echo "a jour ($(git rev-parse --short HEAD))"
  else
    echo "impossible -> on garde la version locale ($(git rev-parse --short HEAD))"
  fi
fi

# Une mise a jour tiree par le minuteur attend peut-etre d'etre appliquee : c'est
# CE demarrage qui l'applique.
MARQUEUR=${SAFEDESK_MARQUEUR:-/var/lib/safedesk/maj-en-attente}
if [ -f "$MARQUEUR" ]; then
  echo "[maj] $(cat "$MARQUEUR")"
  rm -f "$MARQUEUR" 2>/dev/null || true
fi

# L'horloge : une horloge fausse est une panne silencieuse, et sur un serveur elle
# fausse en plus tous les horodatages que les autres machines lisent.
if command -v timedatectl >/dev/null 2>&1; then
  if [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo inconnu)" != "yes" ]; then
    echo "[attention] horloge NON synchronisee. Corriger avec :"
    echo "            sudo ./scripts/setup-hote.sh"
  fi
fi

export RENDER_PROFILE=zz-no-gpu
FILES=(-f docker-compose.yml -f docker-compose.remote.yml -f docker-compose.av.yml)

echo "[detect] profil distant, rendu logiciel"
docker compose "${FILES[@]}" up -d
echo
echo "Bureau distant en place (rendu : $RENDER_PROFILE)"
