#!/bin/sh
[ -r /etc/default/locale ] && . /etc/default/locale && export LANG LANGUAGE
export XDG_CURRENT_DESKTOP=KDE XDG_SESSION_DESKTOP=KDE DESKTOP_SESSION=plasma
# SafeDesk : repartir avec un Chrome propre a chaque session RDP. Sinon le lancement
# de Chrome sur :10 s'accroche a l'instance de fond (bureau Selkies :1) et reste invisible.
pkill -x chrome 2>/dev/null
rm -f /config/.config/google-chrome/Singleton* /config/.config/chromium/Singleton* 2>/dev/null
exec dbus-launch --exit-with-session startplasma-x11