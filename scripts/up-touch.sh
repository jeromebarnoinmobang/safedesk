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

if [ ! -f /etc/polkit-1/rules.d/50-safedesk-touch.rules ]; then
  echo "[touch] ATTENTION : regle polkit absente -> kwin ne pourra pas activer la session."
  echo "         Poser une fois :  sudo SAFEDESK_TOUCH=1 ./scripts/setup-hote.sh"
fi

# Le casque Bluetooth se reconnecte avant le son de la session au demarrage :
# un service utilisateur le reconnecte ensuite (voir le fichier). Sans sudo.
# Seulement lance a la main par l'utilisateur du bureau : au boot, c'est
# safedesk-stack.service (root, sans HOME) qui appelle ce script, et le service
# est deja installe dans le home de pi. Le 26/10/2026, ce bloc sans garde a fait
# echouer le demarrage du bureau (« HOME: unbound variable », set -u).
if [ "$(id -u)" != 0 ] && [ -n "${HOME:-}" ]; then
  mkdir -p "$HOME/.config/systemd/user"
  cp files/systemd/user/safedesk-bt-audio.service "$HOME/.config/systemd/user/"
  systemctl --user daemon-reload 2>/dev/null && systemctl --user enable safedesk-bt-audio.service >/dev/null 2>&1     || echo "[touch] ATTENTION : service safedesk-bt-audio non active (systemctl --user indisponible)"
fi

CMD=("$@"); [ ${#CMD[@]} -eq 0 ] && CMD=(up -d)
# Le script du service est copie par s6 au demarrage du conteneur : un changement
# de son contenu exige de RECREER le conteneur, sinon l'ancienne copie tourne.
[ "${CMD[0]}" = "up" ] && CMD+=(--force-recreate)
docker compose "${FILES[@]}" "${CMD[@]}"
