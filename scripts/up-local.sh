#!/usr/bin/env bash
# Lance le bureau KDE en local, avec GPU si le rendu GPU est REELLEMENT disponible.
set -euo pipefail
cd "$(dirname "$0")/.."

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

# Camera USB : passee au conteneur si presente cote hote (Linux natif uniquement).
# Le micro n a pas besoin de device : il arrive par la redirection RDP (voir docker-compose.av.yml).
if [ -e /dev/video0 ]; then
  echo "[detect] camera USB -> passthrough /dev/video0"
  FILES+=(-f docker-compose.av.yml)
fi

docker compose "${FILES[@]}" up -d
echo
echo "Bureau : http://localhost:3000   (rendu : $RENDER_PROFILE)"