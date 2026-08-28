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

# --- 0. Outils indispensables -------------------------------------------------
#
# Constate le 21/08/2026 : « make » n'etait pas installe sur la station, donc
# « make local » et « make hote » — l'interface documentee de ce depot — echouaient
# sur « make: not found ». Une relance du bureau lancee en tache de fond a donc
# echoue en silence : rien ne s'est passe, et rien ne l'a dit.
for outil in make git curl; do
  if ! command -v "$outil" >/dev/null 2>&1; then
    echo "[outils] $outil manquant -> installation"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$outil"
  fi
done
echo "[outils] make, git, curl presents"

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

# --- 3 bis. Le service de demarrage du bureau ---------------------------------
#
# Il lançait une liste de fichiers compose ECRITE A LA MAIN, sans l'override GPU ni
# l'override camera. A chaque demarrage il recreait donc le conteneur sans camera,
# effaçant ce que « make local » venait de faire. Desormais les deux chemins
# appellent le meme script : il n'y a plus qu'une facon de demarrer le bureau.
# QUEL PROFIL ? Un poste et un VPS ne se lancent pas pareil : le poste publie des
# ports sur localhost et passe la camera, le VPS passe par Traefik et n'a pas d'USB.
# Installer le mauvais chemin sur le VPS lui couperait son reseau.
#
# L'ordre va du plus explicite au plus devine :
#   1. SAFEDESK_PROFIL=local|remote, si l'operateur l'a dit ;
#   2. sinon, ce que le conteneur qui TOURNE utilise deja — la verite du terrain ;
#   3. sinon, local, qui est le cas courant.
PROFIL=${SAFEDESK_PROFIL:-}
if [ -z "$PROFIL" ]; then
  fichiers=$(docker inspect mobang-desktop \
    --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}' 2>/dev/null || true)
  case "$fichiers" in
    *remote.yml*) PROFIL=remote ;;
    *)            PROFIL=local ;;
  esac
  echo "[bureau] profil devine depuis le conteneur en cours : $PROFIL"
else
  echo "[bureau] profil impose : $PROFIL"
fi

case "$PROFIL" in
  remote) LANCEUR="$RACINE/scripts/up-remote.sh"; ARRET="docker compose -f docker-compose.yml -f docker-compose.remote.yml -f docker-compose.av.yml down" ;;
  local)  LANCEUR="$RACINE/scripts/up-local.sh";  ARRET="docker compose -f docker-compose.yml -f docker-compose.local.yml down" ;;
  *)      echo "SAFEDESK_PROFIL inconnu : $PROFIL (attendu local ou remote)" >&2; exit 1 ;;
esac

echo "[bureau] service de demarrage -> $LANCEUR"
sed -e "s|^WorkingDirectory=.*|WorkingDirectory=${RACINE}|" \
    -e "s|^ExecStart=.*|ExecStart=${LANCEUR}|" \
    -e "s|^ExecStop=.*|ExecStop=/usr/bin/${ARRET}|" \
    "$RACINE/files/systemd/safedesk-stack.service" > /etc/systemd/system/safedesk-stack.service
systemctl daemon-reload
systemctl enable safedesk-stack.service >/dev/null 2>&1
echo "[bureau] $(systemctl is-enabled safedesk-stack.service 2>/dev/null)"


# --- 3 ter. Le Bluetooth du Raspberry Pi 5 ------------------------------------
#
# Uniquement sur Pi 5, ou le bureau pilote l adaptateur Bluetooth de l HOTE par le
# bus systeme D-Bus. Le pourquoi est dans docker-compose.pi5.yml : un controleur
# Bluetooth appartient a un NAMESPACE RESEAU, le conteneur ne peut donc pas avoir
# le sien, quels que soient les montages.
#
# CE QUE POLKIT BLOQUE SANS CETTE REGLE, et c est une panne parfaitement muette :
# BlueZ ne confie l appairage qu a une session locale « active » au sens de logind.
# Un client qui arrive par le socket D-Bus depuis un conteneur n a AUCUNE session.
# Le bureau voit donc les peripheriques, affiche la liste, propose d appairer — et
# l appairage echoue sans message exploitable. La regle rend le droit explicite, et
# le limite au seul compte qui fait tourner le bureau (PUID du .env, 1000 par
# defaut) : ce n est pas un blanc-seing pour toute la machine.
MODELE_HOTE=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo '')
case "$MODELE_HOTE" in
  *"Raspberry Pi 5"*)
    PUID_BUREAU=$(grep -E '^PUID=' "$RACINE/.env" 2>/dev/null | cut -d= -f2)
    PUID_BUREAU=${PUID_BUREAU:-1000}
    COMPTE_BUREAU=$(getent passwd "$PUID_BUREAU" | cut -d: -f1)
    if [ -z "$COMPTE_BUREAU" ]; then
      echo "[bluetooth] aucun compte pour l UID $PUID_BUREAU -> regle polkit non posee"
    else
      if ! systemctl is-enabled bluetooth >/dev/null 2>&1; then
        echo "[bluetooth] service bluetooth non actif -> activation"
        systemctl enable --now bluetooth >/dev/null 2>&1 || true
      fi
      cat > /etc/polkit-1/rules.d/51-safedesk-bluetooth.rules <<REGLE
// SafeDesk — pose par scripts/setup-hote.sh, ne pas editer a la main.
// Autorise le compte qui fait tourner le bureau conteneurise a piloter BlueZ.
// Sans cette regle, l appairage echoue en silence : le client arrive par le
// socket D-Bus depuis un conteneur, donc sans session logind « active », et
// polkit refuse par defaut.
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("org.bluez.") === 0 &&
        subject.user === "$COMPTE_BUREAU") {
        return polkit.Result.YES;
    }
});
REGLE
      chmod 0644 /etc/polkit-1/rules.d/51-safedesk-bluetooth.rules
      systemctl restart polkit >/dev/null 2>&1 || true
      echo "[bluetooth] adaptateur de l hote pilotable par « $COMPTE_BUREAU » depuis le bureau"
    fi
    ;;
esac

# --- 4. Verdict ---------------------------------------------------------------
echo
timedatectl | grep -E 'Local time|Universal time|RTC time|synchronized|NTP service'
echo
echo "Machine     : $(hostname)"
echo "Mise a jour : $(systemctl list-timers safedesk-maj.timer --no-legend 2>/dev/null | awk '{print $1, $2, $3}' || echo 'minuteur non actif')"
echo
echo "Termine. Le bureau peut demarrer :  make local"
