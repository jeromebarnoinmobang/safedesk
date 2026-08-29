#!/bin/bash
# RENVOI — ce script est REMPLACÉ depuis le 26/08/2026.
#
# POURQUOI IL A ÉTÉ RETIRÉ, ET C'EST MESURÉ (audit du 26/08) :
#
#  1. Sa boucle de supervision ne surveillait QUE la sortie de `ssh`. Une session ssh
#     en parfaite santé qui redirige vers des ports locaux MORTS ne produisait aucune
#     alerte : le poste se croyait publié pendant que openwork-api.mobang.fr,
#     openwork.mobang.fr et voice.mobang.fr rendaient 502. C'est la panne du 25-26/08,
#     et rien dans ce script n'avait de quoi la nommer.
#
#  2. `stop` tuait le SUPERVISEUR, pas le ssh. Le PID écrit dans le pidfile était
#     celui de la boucle (`echo $$`) ; le `ssh -N` enfant survivait et continuait de
#     tenir les trois ports distants. Le script imprimait « tunnel arrêté » et
#     sortait 0. Toute relance mourait ensuite en boucle sous ExitOnForwardFailure,
#     contre un orphelin invisible.
#
# Le tunnel inverse fait désormais partie de la chaîne (`safework-chaine`), qui le
# vérifie par ce qu'il TRANSPORTE et non par la survie de ssh, et qui ne publie plus
# un renvoi vers un port éteint. Voir safedesk/le depot prive safework, poste/docs/PLAN-OPENWORK.md.
exec /usr/local/bin/safework-chaine "${1:-etat}"
