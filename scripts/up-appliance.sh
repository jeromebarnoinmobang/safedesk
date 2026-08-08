#!/usr/bin/env bash
# Demarre le stack SafeDesk sur l APPLIANCE (appele par safedesk-stack.service).
# Compose la liste des overrides selon le materiel REELLEMENT present au boot :
# la camera n est passee que si elle est branchee (sinon compose echouerait au demarrage).
set -euo pipefail
cd "$(dirname "$0")/.."

FILES=(-f docker-compose.yml -f docker-compose.local.yml)
# Au boot, laisser a udev le temps d enumerer la camera USB (sinon test negatif a tort).
command -v udevadm >/dev/null && udevadm settle -t 5 2>/dev/null || true
if [ -e /dev/video0 ]; then
  echo "[detect] camera USB -> passthrough /dev/video0"
  FILES+=(-f docker-compose.av.yml)
fi

CMD=("$@")
[ ${#CMD[@]} -eq 0 ] && CMD=(up -d)
exec docker compose "${FILES[@]}" "${CMD[@]}"
