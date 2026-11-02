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

## Moonlight mode (Mobang VPS)

The Mobang Pi streams the VPS through Moonlight (Flatpak) over the private VPC instead
of the Chromium kiosk. As the `pi` user:

```sh
install -D -m 0755 thin-client/bin/safedesk-moonlight ~/.local/bin/safedesk-moonlight
install -D -m 0644 thin-client/openbox-autostart ~/.config/openbox/autostart
install -D -m 0644 thin-client/moonlight-safedesk.desktop ~/.local/share/applications/moonlight-safedesk.desktop
printf '%s\n' '<private Sunshine address>' > ~/.config/safedesk-thin-client/moonlight-host
sudo install -m 0644 thin-client/lightdm-autologin.conf /etc/lightdm/lightdm.conf.d/60-safedesk-autologin.conf
touch /etc/safedesk/thin-client   # keeps safedesk-stack.service from starting the local desktop
docker stop mobang-desktop mobang-desktop-sync
```

Roll back with `rm /etc/safedesk/thin-client` and `sudo systemctl restart safedesk-stack`.

Pair once with `flatpak run com.moonlight_stream.Moonlight pair <host> --pin <4 digits>`
and submit the same PIN to Sunshine (`POST /api/pin` on port 47990, or its web UI).
After that, every graphical login waits for Sunshine, streams the `Desktop` app at
1024x768/30 fps/3 Mbps (override with `SAFEDESK_MOONLIGHT_OPTIONS`), and restarts the
stream when it ends. A stream that drops mid-session shows Moonlight's error dialog;
one tap on OK starts the next attempt.

Touch, mouse and keyboard reach the VPS desktop through Sunshine's uinput devices,
replayed into Xvfb by the `sunshine-input` service (one finger = left button: tap =
click, drag = drag). Its log lines start with `[sunshine-input]` in `docker logs`.

`moonlight pair` needs the real X session (`DISPLAY=:0`): under
`QT_QPA_PLATFORM=offscreen` it never stores the server certificate.

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
