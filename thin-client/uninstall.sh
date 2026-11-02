#!/bin/sh
# Disable the kiosk. --purge also removes only the thin-client URL setting.
set -eu

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/safedesk-thin-client"
autostart="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/safedesk-thin-client.desktop"

rm -f "$autostart" "$HOME/.local/bin/safedesk-thin-client"
if [ "${1:-}" = "--purge" ]; then
  rm -rf "$config_dir"
fi

printf '%s\n' "SafeDesk thin-client autostart disabled. No local Docker, data or browser profile was removed."
