#!/usr/bin/env bash
#
# SafeDesk Appliance — transforme un Debian minimal en terminal SafeDesk.
# Au boot : Docker lance le conteneur mobang-desktop, puis une session X ouvre
# xfreerdp en plein ecran sur 127.0.0.1:3389 -> le bureau KDE apparait.
#
# Materiel de reference : Intel i9-7940X | NVIDIA RTX 3080 | Realtek ALC1220 + casque USB | Intel I219-V
# Usage : sudo bash setup.sh   (ou  SAFEDESK_PASSWORD=xxx sudo -E bash setup.sh)
#
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "A lancer en root : sudo bash setup.sh"; exit 1; }

REPO_URL="${SAFEDESK_REPO:-https://github.com/jeromebarnoinmobang/safedesk.git}"
APP_DIR="/opt/safedesk"
KUSER="safedesk"
. /etc/os-release
CODENAME="${VERSION_CODENAME:-trixie}"

echo "############ SafeDesk Appliance — $CODENAME ############"

echo "== [1/9] Depots (contrib non-free non-free-firmware) =="
if [ -f /etc/apt/sources.list.d/debian.sources ]; then
  sed -i "s/^Components:.*/Components: main contrib non-free non-free-firmware/" /etc/apt/sources.list.d/debian.sources
else
  sed -i -E "s/ main$/ main contrib non-free non-free-firmware/" /etc/apt/sources.list || true
fi
apt-get update

echo "== [2/9] Noyau, firmwares, base =="
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  linux-image-amd64 firmware-linux firmware-realtek firmware-misc-nonfree \
  ca-certificates curl git sudo pciutils usbutils locales network-manager

echo "== [3/9] Pilote NVIDIA (RTX 3080) =="
DEBIAN_FRONTEND=noninteractive apt-get install -y nvidia-driver || echo "!! NVIDIA KO -> fallback nouveau/modesetting"

echo "== [4/9] Docker + compose =="
if ! command -v docker >/dev/null; then
  install -m0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $CODENAME stable" > /etc/apt/sources.list.d/docker.list
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi
systemctl enable docker

echo "== [5/9] X minimal + FreeRDP + audio PipeWire =="
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  xserver-xorg-core xserver-xorg-input-libinput xinit x11-xserver-utils openbox \
  pipewire pipewire-pulse wireplumber pulseaudio-utils
DEBIAN_FRONTEND=noninteractive apt-get install -y xserver-xorg-video-nvidia 2>/dev/null || true
DEBIAN_FRONTEND=noninteractive apt-get install -y freerdp3-x11 || DEBIAN_FRONTEND=noninteractive apt-get install -y freerdp2-x11

echo "== [6/9] Utilisateur kiosque + autologin tty1 =="
id "$KUSER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$KUSER"
usermod -aG video,audio,render,input,docker "$KUSER"
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $KUSER --noclear %I \$TERM
EOF

echo "== [7/9] Identifiants RDP (hors repo, dans /etc/safedesk) =="
mkdir -p /etc/safedesk
if [ ! -f /etc/safedesk/kiosk.env ]; then
  cat > /etc/safedesk/kiosk.env <<EOF
RDP_HOST=127.0.0.1:3389
RDP_USER=abc
RDP_PASSWORD=${SAFEDESK_PASSWORD:-REDACTED}
EOF
  chmod 600 /etc/safedesk/kiosk.env
fi

echo "== [8/9] SafeDesk : repo + image + service au boot =="
if [ ! -d "$APP_DIR/.git" ]; then git clone "$REPO_URL" "$APP_DIR"; else git -C "$APP_DIR" pull --ff-only || true; fi
# .env du compose (DESKTOP_PASSWORD vient de /etc/safedesk/kiosk.env — jamais dans le repo)
. /etc/safedesk/kiosk.env
cat > "$APP_DIR/.env" <<ENVEOF
PUID=1000
PGID=1000
TZ=Europe/Paris
DESKTOP_USER=jerome
DESKTOP_PASSWORD=$RDP_PASSWORD
COMPOSE_PROJECT_NAME=mobang-desktop
INSTALL_CHROME=true
INSTALL_CLAUDE=true
INSTALL_SUNSHINE=false
INSTALL_FORGE=false
SAFEDESK_FORGE_REMOTE=https://github.com/jeromebarnoinmobang/safedesk.git
SAFEDESK_NAME=SafeDesk de Jerome
SAFEDESK_URL=https://desktop.mobang.fr
SAFEDESK_APP_URL=https://github.com/jeromebarnoinmobang/safedesk/releases/download/app-v0.1.0/SafeDesk-0.1.0.apk
ENVEOF
chmod 600 "$APP_DIR/.env"
docker pull mobang/desktop:kde 2>/dev/null || (cd "$APP_DIR" && docker compose -f docker-compose.yml -f docker-compose.local.yml build) || true
cat > /etc/systemd/system/safedesk-stack.service <<EOF
[Unit]
Description=SafeDesk desktop container stack
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target
[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/docker compose -f docker-compose.yml -f docker-compose.local.yml up -d
ExecStop=/usr/bin/docker compose -f docker-compose.yml -f docker-compose.local.yml down
[Install]
WantedBy=multi-user.target
EOF
systemctl enable safedesk-stack.service

echo "== [9/9] Kiosque : X + xfreerdp plein ecran, reconnexion auto =="
cat > /home/$KUSER/.bash_profile <<'EOF'
if [ -z "${DISPLAY:-}" ] && [ "$(tty)" = "/dev/tty1" ]; then
  exec startx >/tmp/startx.log 2>&1
fi
EOF
cat > /home/$KUSER/.xinitrc <<'EOF'
#!/bin/sh
xset s off -dpms; xset s noblank
openbox &
: # curseur visible (pas d unclutter)
. /etc/safedesk/kiosk.env
FRDP="$(command -v xfreerdp3 || command -v xfreerdp)"
# resolution FIXE (pas de /dynamic-resolution : ca casse le socket audio cote serveur)
while true; do
  "$FRDP" /v:"$RDP_HOST" /u:"$RDP_USER" /p:"$RDP_PASSWORD" /multimon \
    /sound:sys:pulse /microphone:sys:pulse +clipboard /gfx:rfx \
    -grab-keyboard /cert:ignore /log-level:WARN >/tmp/frdp.log 2>&1
  sleep 3
done
EOF
chmod +x /home/$KUSER/.xinitrc
chown -R $KUSER:$KUSER /home/$KUSER
chown -R $KUSER:$KUSER /etc/safedesk 2>/dev/null || true

echo ""
echo "############################################################"
echo " OK. 'reboot' -> le bureau SafeDesk s'ouvre seul, plein ecran + son."
echo " Identifiants : /etc/safedesk/kiosk.env | Logs : /tmp/startx.log /tmp/frdp.log"
echo "############################################################"