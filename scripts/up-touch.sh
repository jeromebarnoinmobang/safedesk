#!/usr/bin/env bash
# Demarre SafeDesk en mode TACTILE : Plasma sur l'ecran branche a la machine.
#   scripts/up-touch.sh            (ou : scripts/up-touch.sh down)
# Voir docker-compose.touch.yml pour le pourquoi.
set -euo pipefail
cd "$(dirname "$0")/.."

FILES=(-f docker-compose.yml -f docker-compose.local.yml)
if grep -q "Raspberry Pi 5" /proc/device-tree/model 2>/dev/null; then
  export INSTALL_BLUETOOTH=true
  FILES+=(-f docker-compose.pi5.yml)
fi
FILES+=(-f docker-compose.touch.yml)

# L'ecran ne peut avoir qu'UN maitre : le kiosque X de l'hote (startx + xfreerdp)
# doit etre arrete avant que kwin prenne le DRM.
if pgrep -u "$USER" -x Xorg >/dev/null 2>&1; then
  echo "[touch] kiosque X de l'hote detecte -> arret"
  pkill -u "$USER" -x xfreerdp3 2>/dev/null || true
  pkill -u "$USER" -x xfreerdp 2>/dev/null || true
  pkill -u "$USER" -x Xorg 2>/dev/null || true
  sleep 2
fi

# Marqueur lu par le kiosque de l'hote (.bash_profile de l'appliance) : tant qu'il
# existe, l'autologin tty1 ne relance PAS startx au prochain demarrage.
case "${1:-up}" in
  down) rm -f /etc/safedesk/touch 2>/dev/null || sudo -n rm -f /etc/safedesk/touch 2>/dev/null || true ;;
  *)    if ! { [ -f /etc/safedesk/touch ] || touch /etc/safedesk/touch 2>/dev/null || sudo -n touch /etc/safedesk/touch 2>/dev/null; }; then
          echo "[touch] ATTENTION : /etc/safedesk/touch non pose (droits). Sans lui, l'autologin"
          echo "         tty1 relance startx et reprend l'ecran. Poser a la main :"
          echo "           sudo touch /etc/safedesk/touch"
        fi ;;
esac

CMD=("$@"); [ ${#CMD[@]} -eq 0 ] && CMD=(up -d)
docker compose "${FILES[@]}" "${CMD[@]}"
