#!/usr/bin/env bash
# Lance le bureau KDE en local, avec GPU si le rendu GPU est REELLEMENT disponible.
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGE=$(grep -oE 'image:\s*\S*webtop\S*' docker-compose.yml | head -1 | awk '{print $2}')
PROBE='if [ -e /dev/dxg ] && [ -f /usr/lib/wsl/lib/libd3d12.so ]; then echo WSL; elif [ -d /dev/dri ]; then echo DRI; else echo NONE; fi'

printf '[detect] capacite de rendu GPU... '
MODE=$(docker run --rm --gpus all -v /usr/lib/wsl:/usr/lib/wsl:ro --entrypoint sh "$IMAGE" -c "$PROBE" 2>/dev/null | tail -1 || echo NONE)
[ "$MODE" = "NONE" ] && MODE=$(docker run --rm --entrypoint sh "$IMAGE" -c "$PROBE" 2>/dev/null | tail -1 || echo NONE)

FILES=(-f docker-compose.yml -f docker-compose.local.yml)
case "$MODE" in
  WSL) echo "GPU via WSL2/d3d12"; export RENDER_PROFILE=zz-gpu-wsl; FILES+=(-f docker-compose.gpu-wsl.yml) ;;
  DRI) echo "GPU via /dev/dri";   export RENDER_PROFILE=zz-gpu-dri; FILES+=(-f docker-compose.gpu-dri.yml) ;;
  *)   echo "aucun rendu GPU -> rendu logiciel"; export RENDER_PROFILE=zz-no-gpu ;;
esac

docker compose "${FILES[@]}" up -d
echo
echo "Bureau : http://localhost:3000   (rendu : $RENDER_PROFILE)"