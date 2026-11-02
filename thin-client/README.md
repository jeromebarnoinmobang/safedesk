# SafeDesk thin client (Raspberry Pi)

This is the lightweight SafeDesk role: the Pi displays a SafeDesk desktop running
elsewhere. It does **not** run Docker, Syncthing for the desktop home, or a second
browser profile. One host owns the state; for the Mobang deployment, that host is the
VPS.

## Install safely

On the Pi, as its graphical user:

```sh
git clone https://github.com/jeromebarnoinmobang/safedesk.git
cd safedesk
./thin-client/install.sh --install-browser https://your-safedesk-host/
```

Use an HTTPS endpoint reachable only through the intended private network or protected
reverse proxy. Never put a password in the URL or commit a deployment address into this
public repository.

The installer only adds a Chromium kiosk launcher and autostart entry. It does not stop,
remove, or alter an existing local SafeDesk/Docker installation. After signing in once,
the kiosk opens the stream automatically on graphical login and restarts Chromium after
a crash or disconnect.

## Validate before retiring the local stack

1. Reboot or log out/in and confirm the remote desktop opens.
2. Check keyboard, mouse, audio, browser login, Wi-Fi reconnect and VPN reconnect.
3. Confirm the Pi has no active `desktop` or `home-sync` container.
4. Only then stop/archive the previous local stack, using its documented rollback path.

## Roll back

Disable the kiosk with:

```sh
./thin-client/uninstall.sh
```

Use `--purge` only to remove the thin-client URL setting too. Neither command touches
the legacy SafeDesk containers, the user home, or Chromium's profile.
