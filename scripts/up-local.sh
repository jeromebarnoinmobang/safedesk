#!/usr/bin/env bash
# Lance le bureau KDE en local, avec GPU si le rendu GPU est REELLEMENT disponible.
set -euo pipefail
cd "$(dirname "$0")/.."

# MISE A JOUR DU DEPOT AVANT DE DEMARRER, mais JAMAIS AU PRIX DU BUREAU.
#
# Le bureau doit demarrer meme sans reseau, meme si GitHub est injoignable, meme si
# l arbre local a divergé. Chaque garde-fou ci-dessous protege un cas qui, sinon,
# laisserait Jerome SANS environnement de travail :
#   --ff-only            : jamais de commit de fusion ni de conflit a resoudre a
#                          l aveugle au demarrage ; si ca ne s avance pas tout
#                          seul, on garde la version locale et on le dit ;
#   GIT_TERMINAL_PROMPT=0: le distant est en HTTPS. Sans ca, une demande
#                          d identifiants BLOQUERAIT le script indefiniment ;
#   timeout 60           : un reseau qui pend ne doit pas retarder le bureau ;
#   if ... else          : l echec est ANNONCE, jamais fatal.
#
# Prealable regle le 21/08/2026 : android/.gradle etait suivi par git et reecrit a
# chaque compilation, donc l arbre etait sale en permanence et le pull aurait
# echoue a tous les coups. Ces artefacts sont desormais ignores.
if git rev-parse --git-dir >/dev/null 2>&1; then
  printf '[maj] mise a jour du depot... '
  if GIT_TERMINAL_PROMPT=0 timeout 60 git pull --ff-only --quiet 2>/dev/null; then
    echo "a jour ($(git rev-parse --short HEAD))"
  else
    echo "impossible (reseau, identifiants ou divergence) -> on garde la version locale ($(git rev-parse --short HEAD))"
  fi
fi

# L HORLOGE DE L HOTE, parce qu une horloge fausse est une panne SILENCIEUSE.
#
# Constate le 21/08/2026 : cette machine avait deux heures d avance en absolu. Rien
# ne le montrait — le fuseau valant UTC, l heure AFFICHEE tombait juste par
# coincidence. Mais tout fichier ecrit ici apparaissait deux heures dans le FUTUR
# aux autres machines, ce qui a casse le filigrane du RAG et alimente les conflits
# Syncthing. On ne corrige pas ici (il faut l hote et CAP_SYS_TIME) : on le DIT.
if command -v timedatectl >/dev/null 2>&1; then
  if [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo inconnu)" != "yes" ]; then
    echo "[attention] horloge NON synchronisee : les horodatages de cette machine"
    echo "            peuvent etre faux pour les AUTRES machines sans que rien"
    echo "            ne le montre ici. Corriger une fois pour toutes avec :"
    echo "            sudo ./scripts/setup-hote.sh"
  fi
fi

# Une mise a jour tiree par le minuteur attend peut-etre d etre appliquee : c est
# CE demarrage qui l applique, donc on le dit et on efface le marqueur.
MARQUEUR=${SAFEDESK_MARQUEUR:-/var/lib/safedesk/maj-en-attente}
if [ -f "$MARQUEUR" ]; then
  echo "[maj] $(cat "$MARQUEUR")"
  rm -f "$MARQUEUR" 2>/dev/null || true
fi

IMAGE=alpine:3.20   # sonde legere : on ne teste que les devices/libs, pas l app
PROBE='if [ -e /dev/dxg ] && [ -f /usr/lib/wsl/lib/libd3d12.so ]; then echo WSL; elif [ -d /dev/dri ]; then echo DRI; else echo NONE; fi'

printf '[detect] capacite de rendu GPU... '
docker image inspect "$IMAGE" >/dev/null 2>&1 || docker pull "$IMAGE" >/dev/null 2>&1
MODE=$(docker run --rm --gpus all -v /usr/lib/wsl:/usr/lib/wsl:ro "$IMAGE" sh -c "$PROBE" 2>/dev/null | grep -oE "^(WSL|DRI|NONE)$" | tail -1 || echo NONE)
[ "$MODE" = "NONE" ] && MODE=$(docker run --rm -v /usr/lib/wsl:/usr/lib/wsl:ro "$IMAGE" sh -c "$PROBE" 2>/dev/null | grep -oE "^(WSL|DRI|NONE)$" | tail -1 || echo NONE)

FILES=(-f docker-compose.yml -f docker-compose.local.yml)
case "$MODE" in
  WSL) echo "GPU via WSL2/d3d12"; export RENDER_PROFILE=zz-gpu-wsl; FILES+=(-f docker-compose.gpu-wsl.yml) ;;
  DRI) echo "GPU via /dev/dri";   export RENDER_PROFILE=zz-gpu-dri; FILES+=(-f docker-compose.gpu-dri.yml) ;;
  *)   echo "aucun rendu GPU -> rendu logiciel"; export RENDER_PROFILE=zz-no-gpu ;;
esac

# Camera USB : l override AV est pose SANS CONDITION sur Linux natif.
#
# POURQUOI CE N EST PLUS « si /dev/video0 existe », et c est une reunion manquee qui
# l impose (21/08/2026). L override existe justement pour le HOTPLUG : il monte le
# devtmpfs de l hote, donc une camera branchee A CHAUD apparait dans le conteneur
# sans le recreer. Mais la DECISION de le poser restait un test au demarrage — donc
# une camera absente au boot ne revenait JAMAIS, quoi qu on branche ensuite. Le
# hotplug ne rattrapait que les sessions demarrees avec la camera deja la, c est-a-dire
# exactement les cas ou il ne servait a rien.
#
# Le poser toujours ne coute rien quand il n y a pas de camera : monter /dev et
# declarer une liste blanche cgroup ne cree aucun peripherique. Ca REND simplement
# vrai ce que son propre commentaire promet.
#
# Le micro n a pas besoin de device : il arrive par la redirection RDP (voir docker-compose.av.yml).
#
# WSL est exclu : l override est ecrit pour un devtmpfs Linux natif, et monter /dev
# depuis WSL n a jamais ete essaye. On ne change pas un chemin qu on ne mesure pas.
if [ "$MODE" != "WSL" ]; then
  FILES+=(-f docker-compose.av.yml)
  if [ -e /dev/video0 ]; then
    echo "[detect] camera detectee -> /dev/video0"
  else
    echo "[detect] aucune camera pour l instant -> hotplug actif, il suffira de la brancher"
  fi
fi

docker compose "${FILES[@]}" up -d
echo
echo "Bureau : http://localhost:3000   (rendu : $RENDER_PROFILE)"