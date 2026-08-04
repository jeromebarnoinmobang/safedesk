#!/bin/sh
[ -r /etc/default/locale ] && . /etc/default/locale && export LANG LANGUAGE
export XDG_CURRENT_DESKTOP=KDE XDG_SESSION_DESKTOP=KDE DESKTOP_SESSION=plasma
exec dbus-launch --exit-with-session startplasma-x11