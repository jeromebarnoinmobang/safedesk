#!/bin/bash
# SafeDesk — sauvegarde / restauration de l'etat fonctionnel de Claude Desktop.
#
# Ce qui est sauvegarde va PAR PAIRE, et c'est tout l'interet du script :
#   - le profil  ~/.config/Claude        (sessions, conversations, cookies CHIFFRES)
#   - le trousseau ~/.local/share/kwalletd (la CLE qui dechiffre ces cookies)
# Restaurer l'un sans l'autre redonne l'ecran "Sign In".
#
# Usage (sur l'hote de l'appliance) :
#   ./claude-state.sh save [libelle]   sauvegarde l'etat courant
#   ./claude-state.sh list             liste les sauvegardes
#   ./claude-state.sh restore <fichier> restaure (arrete puis relance Claude)

set -euo pipefail

CT=mobang-desktop
BK=/config/.backups
IN="docker exec -u 0 $CT bash -c"

usage() { sed -n '2,18p' "$0"; exit 1; }

claude_pid() {
  docker exec -u 0 $CT bash -c '
    link=$(readlink /config/.config/Claude/SingletonLock 2>/dev/null) || exit 0
    pid=${link##*-}
    kill -0 "$pid" 2>/dev/null && printf "%s" "$pid"' </dev/null
}

stop_claude() {
  local pid; pid=$(claude_pid)
  [ -z "$pid" ] && { echo "Claude n'est pas lance."; return 0; }
  echo "Arret de Claude (pid $pid)..."
  docker exec -u 0 $CT bash -c "
    kill -TERM $pid 2>/dev/null || true
    for i in \$(seq 1 20); do kill -0 $pid 2>/dev/null || break; sleep 1; done
    kill -0 $pid 2>/dev/null && kill -9 $pid || true
    rm -f /config/.config/Claude/Singleton{Lock,Socket,Cookie}" </dev/null
}

case "${1:-}" in
  save)
    label=${2:-}
    stamp=$(date +%Y-%m-%d-%H%M)${label:+-$label}
    echo "Sauvegarde de l'etat vers $BK/claude-state-$stamp.tgz"
    $IN "
      mkdir -p $BK
      tar czf $BK/claude-state-$stamp.tgz \
        -C /config .config/Claude .local/share/kwalletd \
        --exclude='.config/Claude/Cache' --exclude='.config/Claude/Code Cache' \
        --exclude='.config/Claude/GPUCache' --exclude='.config/Claude/DawnGraphiteCache' \
        --exclude='.config/Claude/DawnWebGPUCache' --exclude='.config/Claude/Crashpad' \
        --exclude='.config/Claude/logs' --exclude='.config/Claude/blob_storage' 2>/dev/null || true
      chown abc:abc $BK/claude-state-$stamp.tgz
      ls -lh $BK/claude-state-$stamp.tgz" </dev/null
    ;;

  list)
    $IN "ls -lht $BK/ 2>/dev/null | head -20" </dev/null
    ;;

  restore)
    f=${2:-}; [ -z "$f" ] && usage
    case "$f" in /*) ;; *) f="$BK/$f" ;; esac
    $IN "[ -f '$f' ]" </dev/null || { echo "Introuvable : $f"; exit 1; }
    echo "ATTENTION : l'etat courant de Claude va etre remplace par $f"
    read -r -p "Confirmer ? [oui/non] " ok
    [ "$ok" = "oui" ] || { echo "Annule."; exit 1; }
    stop_claude
    $IN "
      mv /config/.config/Claude /config/.config/Claude.avant-restauration.\$(date +%s) 2>/dev/null || true
      tar xzf '$f' -C /config
      chown -R abc:abc /config/.config/Claude /config/.local/share/kwalletd" </dev/null
    echo "Restaure. Relance Claude depuis l'icone du bureau."
    ;;

  *) usage ;;
esac
