#!/bin/sh
# Install the Pi-side SafeDesk kiosk for the current graphical user.
# Deliberately does not stop or delete an existing local SafeDesk installation.
set -eu

usage() {
  printf '%s\n' "Usage: $0 [--install-browser] <https://safe-desk-host/>"
  exit 64
}

install_browser=false
if [ "${1:-}" = "--install-browser" ]; then
  install_browser=true
  shift
fi
[ "$#" -eq 1 ] || usage
url=$1

case "$url" in
  https://* ) ;;
  * ) printf '%s\n' "The SafeDesk stream URL must use HTTPS." >&2; exit 64 ;;
esac

case "$url" in
  *"\n"*|*"\r"* ) printf '%s\n' "The SafeDesk stream URL must be one line." >&2; exit 64 ;;
esac

if [ "$(id -u)" -eq 0 ]; then
  printf '%s\n' "Run this installer as the graphical Pi user, not as root." >&2
  exit 77
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if ! command -v chromium >/dev/null 2>&1 && ! command -v chromium-browser >/dev/null 2>&1; then
  if [ "$install_browser" != true ]; then
    printf '%s\n' "Chromium is not installed. Re-run with --install-browser to install it." >&2
    exit 69
  fi
  sudo apt-get update
  sudo apt-get install -y chromium
fi

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/safedesk-thin-client"
bin_dir="$HOME/.local/bin"
autostart_dir="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
mkdir -p "$config_dir" "$bin_dir" "$autostart_dir"

install -m 0755 "$script_dir/bin/safedesk-thin-client" "$bin_dir/safedesk-thin-client"
printf '%s\n' "$url" > "$config_dir/stream-url"
chmod 600 "$config_dir/stream-url"

cat > "$autostart_dir/safedesk-thin-client.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=SafeDesk thin client
Comment=Open the remote SafeDesk desktop at login
Exec=sh -lc 'exec "$HOME/.local/bin/safedesk-thin-client"'
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

printf '%s\n' "Installed. Log out/in (or run ~/.local/bin/safedesk-thin-client) to open SafeDesk."
printf '%s\n' "The existing local SafeDesk has not been modified."
