#!/usr/bin/env bash
# Prerequis HOTE de SafeDesk — ce que le bureau ne peut pas se donner lui-meme.
#
# A lancer UNE FOIS par machine, en root :   sudo ./scripts/setup-hote.sh
# Rejouable sans risque : chaque geste verifie avant d agir.
#
# POURQUOI CE SCRIPT EXISTE. Le 21/08/2026, cette station avait deux heures
# d avance en absolu, et rien ne le montrait : le conteneur n ayant pas de fuseau,
# l heure AFFICHEE tombait juste par coincidence. Mais tout fichier ecrit ici
# apparaissait deux heures dans le FUTUR aux autres machines. Ca a casse le
# filigrane du moteur RAG (qui a du se doter d un garde-fou pour survivre), et ca
# alimente les conflits Syncthing. Une panne parfaitement silencieuse.
#
# La correction a d abord ete faite A LA MAIN — donc elle aurait disparu au
# prochain poste, ou au prochain reinstall. Elle vit ici desormais.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Ce script doit tourner en root :  sudo $0" >&2
  exit 1
fi

# --- 1. L horloge -------------------------------------------------------------
#
# LA CAUSE, et elle est classique en double amorcage : Windows ecrit l heure
# LOCALE dans l horloge materielle (RTC), Linux la lit comme de l UTC. En ete a
# Paris (UTC+2) ca donne exactement deux heures d avance. Sans NTP, l ecart est
# permanent ; avec NTP, il ne dure que quelques secondes apres le demarrage.
#
# Le correctif complet a deux moities : celle-ci (Linux se resynchronise), et une
# cote Windows si le double amorcage continue — poser le DWORD
# HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation\RealTimeIsUniversal a 1
# pour que Windows cesse d ecrire de l heure locale dans le RTC.

echo "[horloge] service de synchronisation..."
if [ "$(timedatectl show -p CanNTP --value)" != "yes" ]; then
  echo "          aucun service NTP installe -> systemd-timesyncd"
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq systemd-timesyncd
else
  echo "          deja disponible"
fi

timedatectl set-ntp true
echo "[horloge] NTP active"

# Amorcage : NTP peut refuser de corriger un ecart enorme, ou mettre longtemps.
# On pose donc l heure une fois depuis une reference reseau si l ecart depasse
# deux minutes, puis on laisse NTP tenir la barre.
#
# LE PIEGE, rencontre en direct le 21/08/2026 : « timedatectl set-time » attend
# l heure LOCALE. Lui passer de l UTC deplace la machine du mauvais cote du
# fuseau — on corrige deux heures d avance en creant deux heures de retard. D ou
# la conversion explicite en heure locale ci-dessous, et pas un « date -u ».
if reference=$(curl -sI --max-time 10 https://www.google.com 2>/dev/null | grep -i '^date:' | cut -d' ' -f2-); [ -n "${reference:-}" ]; then
  attendu=$(date -d "$reference" +%s)
  ecart=$(( $(date +%s) - attendu )); ecart=${ecart#-}
  if [ "$ecart" -gt 120 ]; then
    echo "[horloge] ecart de ${ecart} s avec la reference reseau -> mise a l heure"
    timedatectl set-time "$(date -d "$reference" '+%Y-%m-%d %H:%M:%S')"
  else
    echo "[horloge] ecart de ${ecart} s : rien a corriger"
  fi
else
  echo "[horloge] pas de reference reseau joignable, on s en remet a NTP seul"
fi

# --- 2. Le nom de la machine (optionnel) --------------------------------------
#
# Une station sortie d une installation Windows garde souvent un nom du genre
# « DESKTOP-1BU5G6M », qui ne dit rien a personne et se retrouve dans les
# journaux, les certificats et les noms de peripheriques Syncthing.
# Ne fait rien si SAFEDESK_HOSTNAME n est pas fourni.
if [ -n "${SAFEDESK_HOSTNAME:-}" ] && [ "$(hostname)" != "$SAFEDESK_HOSTNAME" ]; then
  ancien=$(hostname)
  echo "[nom] $ancien -> $SAFEDESK_HOSTNAME"
  cp -a /etc/hosts "/etc/hosts.avant-renommage-$(date +%Y%m%d)"
  hostnamectl set-hostname "$SAFEDESK_HOSTNAME"
  # /etc/hosts doit suivre : un nom qui ne se resout pas rend « sudo » lent et
  # fait echouer des programmes qui interrogent leur propre machine.
  sed -i "s/\b${ancien}\b/${SAFEDESK_HOSTNAME}/g" /etc/hosts
  grep -q "$SAFEDESK_HOSTNAME" /etc/hosts || printf '127.0.1.1\t%s\n' "$SAFEDESK_HOSTNAME" >> /etc/hosts
fi

# --- 3. Mise a jour automatique du depot --------------------------------------
#
# POURQUOI. Le 21/08/2026, le clone de cette station avait QUINZE commits de
# retard — dont le correctif qui lui aurait rendu sa camera pour une reunion. Un
# depot qu on tire a la main est un depot qu on oublie de tirer.
#
# CE QUE LE MINUTEUR NE FAIT PAS : redemarrer le bureau. Jerome travaille dedans ;
# le couper sans prevenir remplacerait un desagrement par une perte de travail. Il
# tire, il pose un marqueur, et « make local » applique quand ca arrange.
#
# A SAVOIR, parce que ca s accepte en connaissance de cause : cette machine
# executera desormais du code tire de GitHub sans qu un humain le relise a chaque
# fois. C est le prix de « se mettre a jour tout seul », et c est un depot prive.

RACINE=$(cd "$(dirname "$0")/.." && pwd)
echo "[maj] installation du minuteur (depot : $RACINE)"
sed "s|^ExecStart=.*|ExecStart=${RACINE}/scripts/maj.sh|" \
    "$RACINE/files/systemd/safedesk-maj.service" > /etc/systemd/system/safedesk-maj.service
install -m 0644 "$RACINE/files/systemd/safedesk-maj.timer" /etc/systemd/system/safedesk-maj.timer
systemctl daemon-reload
systemctl enable --now safedesk-maj.timer >/dev/null 2>&1
echo "[maj] minuteur actif : $(systemctl is-enabled safedesk-maj.timer 2>/dev/null)"

# --- 4. Verdict ---------------------------------------------------------------
echo
timedatectl | grep -E 'Local time|Universal time|RTC time|synchronized|NTP service'
echo
echo "Machine     : $(hostname)"
echo "Mise a jour : $(systemctl list-timers safedesk-maj.timer --no-legend 2>/dev/null | awk '{print $1, $2, $3}' || echo 'minuteur non actif')"
echo
echo "Termine. Le bureau peut demarrer :  make local"
