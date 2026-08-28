#!/bin/bash
# RENVOI — ce script est REMPLACÉ depuis le 26/08/2026.
#
# POURQUOI IL A ÉTÉ RETIRÉ, ET C'EST MESURÉ (audit du 26/08) :
#
#  1. Son contrôle de vie testait le port 14099 — celui de l'ancien fork LOCAL,
#     abandonné le 25/08 au profit du tunnel :14098 vers le VPS. Deux mensonges
#     symétriques : un zombie sur 14099 faisait dire « déjà en route », et une
#     chaîne parfaitement saine faisait déclencher un stop+relance destructeur.
#
#  2. `up() { [ "$(code "$1")" != "000" ]; }` déclarait « en vie » N'IMPORTE QUELLE
#     réponse HTTP — 502, 500, 401, 404 compris. Toute la classe de pannes réellement
#     observée sur ce poste passait donc pour un succès.
#
#  3. Sa relance appelait le `stop` de run-chaine-dev.sh, incapable de tuer vite
#     (motif `vite ` contre un processus nommé `vite.js`). Résultat : serveur tué,
#     front périmé survivant, relance morte sur « Port 14880 is already in use » —
#     et « pile OpenWork prête » imprimé quand même.
#
# Le remplaçant CONSTATE au lieu de déclarer : il lit dans /proc du vite vivant
# l'API que le front appelle réellement, et vérifie que cette API répond.
# Voir safedesk/docs/PLAN-OPENWORK.md.
#
# La chaîne est désormais un service s6 supervisé (`safedesk-openwork`) : elle monte
# au démarrage du conteneur et se répare toutes les 30 s. Ce script n'a plus à
# exister, mais il reste ici pour que rien qui l'appelait encore ne parte en silence.
exec /usr/local/bin/openwork-chaine "${1:-etat}"
