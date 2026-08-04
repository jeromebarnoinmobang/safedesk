#!/usr/bin/env bash
# SafeDesk - provisioning d'un Debian 13 (Trixie) KDE NATIF.
# Reproduit l'environnement du conteneur SafeDesk en natif : Claude Desktop, Chrome,
# VS Code, Node/Claude Code, pilote NVIDIA (RTX 3080), outils de base.
# Usage :  sudo bash provision.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Lance avec sudo : sudo bash $0"; exit 1; }
TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || echo user)}"
export DEBIAN_FRONTEND=noninteractive
echo ">>> Cible : $TARGET_USER"

echo ">>> [1/8] contrib + non-free + maj systeme"
if [ -f /etc/apt/sources.list.d/debian.sources ]; then
  sed -i 's/^Components:.*/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources
elif [ -f /etc/apt/sources.list ]; then
  sed -i 's/ main$/ main contrib non-free non-free-firmware/' /etc/apt/sources.list
fi
apt-get update && apt-get -y upgrade

echo ">>> [2/8] outils de base"
apt-get install -y --no-install-recommends curl wget git gh ca-certificates gnupg \
  apt-transport-https build-essential zip unzip qrencode espeak-ng flatpak

echo ">>> [3/8] pilote NVIDIA (RTX 3080)"
apt-get install -y linux-headers-amd64 nvidia-driver firmware-misc-nonfree || \
  echo "!! NVIDIA KO -> voir https://wiki.debian.org/NvidiaGraphicsDrivers"

echo ">>> [4/8] Claude Desktop"
curl -fsSLo /usr/share/keyrings/claude-desktop-archive-keyring.asc https://downloads.claude.ai/claude-desktop/key.asc
if gpg --show-keys --with-colons /usr/share/keyrings/claude-desktop-archive-keyring.asc | grep -q "31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"; then
  echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main" > /etc/apt/sources.list.d/claude-desktop.list
  apt-get update && apt-get install -y --no-install-recommends claude-desktop desktop-file-utils
  update-desktop-database /usr/share/applications || true
  echo "   (natif : le trousseau KDE/gnome-keyring marche -> login persistant sans bidouille)"
else
  echo "!! cle Claude non verifiee, install ignoree"
fi

echo ">>> [5/8] Google Chrome"
curl -fsSLo /usr/share/keyrings/google-chrome.asc https://dl.google.com/linux/linux_signing_key.pub
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.asc] https://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list
apt-get update && apt-get install -y google-chrome-stable

echo ">>> [6/8] VS Code"
curl -fsSLo /usr/share/keyrings/microsoft.asc https://packages.microsoft.com/keys/microsoft.asc
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.asc] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list
apt-get update && apt-get install -y code

echo ">>> [7/8] Node.js 22 + Claude Code (CLI)"
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs
npm install -g @anthropic-ai/claude-code || echo "!! claude-code KO -> refais : sudo npm i -g @anthropic-ai/claude-code"

echo ">>> [8/8] repo SafeDesk (outils)"
sudo -u "$TARGET_USER" bash -lc "cd ~ && [ -d safedesk ] || git clone https://github.com/jeromebarnoinmobang/safedesk.git"

cat <<"EOF"

============================================================
  SafeDesk natif : provisioning termine.
  1) REDEMARRE (pour charger le pilote NVIDIA).
  2) Lance Claude Desktop (menu K) -> login persistant natif.
  3) Reconfigure tes MCP (second-brain...) dans Claude Desktop.
  4) Chrome : reconnecte ton compte Google pour la sync.
============================================================
EOF