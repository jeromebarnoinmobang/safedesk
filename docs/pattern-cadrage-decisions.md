# Pattern « cadrage » — mémo de décision

Écrit le 19/08/2026. Trace de pourquoi le skill `/cadrage` est fait comme ça, pour la
prochaine fois où l'envie de le complexifier reviendra.

## Ce qui a été retenu, et pourquoi

Quatre ajouts seulement sont **meilleurs** que la méthode déjà pratiquée la semaine du
17/08 (contrat → plan → adversarial → agent par tache → controle éclair → commit → mémoire).
Chacun corrige un échec vécu et payé :

1. **Tester les hypothèses avant de construire**, trié par **cout du test** et non par risque
   perçu. TTS RunPod et CORS auraient été cotés « moyen » la veille de leur chute : coter est
   plus cher que tester. Cout : deux `curl` et une question. Économie : plusieurs jours.
2. **La fiche à en-tetes fixes**, avec `Out of scope — DO NOT`, `Files OWNED / READ ONLY`,
   `Known traps`, et surtout `Deliverable : a report without a commit is a FAILED task`.
   Corrige mécaniquement les agents qui rendaient un rapport sans livrable.
3. **Les pièges connus collés dans chaque brief.** Le `pkill -f` a tué le shell trois fois.
   Cinq lignes recopiées : meilleur rapport valeur/token de tout le corpus.
4. **L'état dérivé du disque + une seule ligne « prochain geste ».** Seul mécanisme qui
   adresse frontalement la cécité temporelle et la mort de session.

Tout le reste du skill est de la plomberie autour de ces quatre points.

## Ce qui a été rejeté, et pourquoi

| Rejeté | Motif |
|---|---|
| **Cotation létalité × incertitude (3×3, seuil « 3 et ≥2 »)** | Machinerie de tri qui remplace une question. Le tag est posé au moment d'ignorance maximale — les deux murs réels seraient passés dessous. Remplacé par : cout du test. |
| **Routeur à 3 tailles avec déclencheurs multiples** | Résout à la taille maximale presque toujours (« ≥ 2 hypothèses OU une dépendance externe » = tout chantier réel). Remplacé par une question non estimative : « puis-je écrire le message de commit avant de commencer ? » |
| **Cartographie systématique à 3-4 agents parallèles** | 180-450 k tokens sur la seule foi d'un succès unique, jamais comparé à 1 agent + `grep`. Défaut ramené à 1 agent ; fan-out sur condition. |
| **Agent synthétiseur séparé** | La session principale lit N fichiers. Un agent entier économisé. |
| **Triple représentation des taches** (plan + fiche + jsonl + Plane) | Le drift naissait au jour 0 : le JSON ne reprenait que 2 des 5 critères. Une seule source : la fiche **est** le payload. |
| **CONSTITUTION.md + PITFALLS.md + CLAUDE.md + mémoire** | Quatre étages pour « les choses permanentes », zéro règle de non-duplication. Réponse : `CLAUDE.md`, point. |
| **Passe 5 du réfuteur (prémortem)** | Le poste le plus cher en tokens, le plus faible en preuve (étude humaine 1989, transfert LLM non démontré). Les passes 1-3 portent le gain chiffré (11 % → 85,4 %). |
| **Nomenclature G0…G7 / P0…P9** | Deux gates réels : hypothèses testées, plan réfuté. Le reste était des étiquettes sur des transitions. |
| **Gate d'arbitrage des 12 constats par Jérôme** | Dithering institutionnalisé sous un autre nom. L'architecte intègre lui-meme et motive ses rejets ; Jérôme lit une ligne et garde un veto. |
| **Vérificateur LLM par tache** | Sur du code correct, le critique naïf produit du faux positif massif ; l'auteur ne peut pas s'auto-juger. Le signal sur le code, c'est l'exécution. |
| **Seuils en minutes ou en lignes prévisionnelles** (« > 1 h », « > 300 lignes », « Must ≤ 50 % de l'effort ») | Demandent une estimation de durée à quelqu'un en cécité temporelle. Sautés en silence, et la discipline de découpage part avec. Remplacés par des seuils comptables. |
| **RICE / WSJF** | Reach ≈ 1, Confidence inventée. Le calcul coute plus qu'il ne rapporte en solo. Tie-breaker unique : « quelle tache tue la plus grosse hypothèse ? » |
| **Écrire le skill avant d'avoir tourné le pattern à la main** | Le méta-chantier est le mode de consommation classique de ce genre de framework. Le skill livré ici est volontairement minimal : 1 SKILL.md, 4 références, 1 script. S'il ne survit pas à deux chantiers, il n'y avait rien à outiller. |

## Les 5 pièges connus du pattern lui-même

1. **Le méta-chantier.** Améliorer le pattern devient le projet. Règle : on ne touche au
   skill qu'après un chantier réel terminé, et seulement pour supprimer ce qui n'a pas servi.
2. **Empiler des plans jamais exécutés.** Cadrer est gratifiant, exécuter ne l'est pas.
   Deux verrous : interdit d'ouvrir un chantier tant qu'un chantier existant a un plan et
   zéro commit ; le plan n'est détaillé que pour les 3 prochaines taches.
3. **Trois chantiers ouverts, aucun fini, aucun mort.** WIP = 1, vérifié par `etat.sh`, plus
   un rite d'abandon déclenché mécaniquement (deux ouvertures de session sans commit) avec
   une question binaire continuer/tuer.
4. **Le spike qui ment de façon plausible.** Verdict TENUE sur un test qui a testé la
   mauvaise condition (pod chaud au lieu de pod froid). Parade : les 3 questions fermées de
   controle appliquées aux spikes autant qu'aux taches.
5. **La sur-cérémonie qui revient par la porte de derrière.** Chaque ajout au pattern doit
   remplir un champ de la fiche de tache. Un artefact qui ne remplit aucun champ est
   supprimé. Un chantier sous 4 taches est mathématiquement perdant : c'est du FLUX, pas un
   chantier.

## Ce qu'on mesure (et rien d'autre)

Trois chiffres à la clôture, deux minutes : taches passées du premier coup · constats du
réfuteur intégrés (sous 30 % deux fois de suite → couper le réfuteur) · taches re-découpées
en cours de route (si ça monte, le gate du plan est trop laxiste).

Rappel de calibrage : l'essai randomisé METR mesure des devs expérimentés **19 % plus lents**
avec l'IA alors qu'ils s'estiment 20 % plus rapides. La sensation de rigueur ne mesure rien.
Seules les taches livrées et committées comptent.

## Sources principales

- GitHub Spec Kit — format de tache, marqueur `[NEEDS CLARIFICATION]`, marqueur `[P]` :
  https://github.com/github/spec-kit/blob/main/spec-driven.md
- Böckeler / Thoughtworks, taxonomie spec-first / anchored / as-source, et le cout de
  cérémonie : https://martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html
- GSD — état projet retourné par un script déterministe, `research/PITFALLS.md`,
  plan-checker comme gate : https://deepwiki.com/gsd-build/get-shit-done
- Anthropic, context engineering (minimal high-signal tokens, sous-agents rendant
  1000-2000 tokens) : https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- Anthropic, multi-agent research system — brief de délégation, cout 3-10× du fan-out :
  https://www.anthropic.com/engineering/multi-agent-research-system
- METR, horizon temporel des taches agentiques (~100 % sous 4 min, < 10 % au-delà de 4 h) :
  https://metr.org/blog/2025-03-19-measuring-ai-ability-to-complete-long-tasks/
- METR, essai randomisé « 19 % plus lents » :
  https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/
- Comparaison comportementale spec↔code, 11,0 % → 85,4 % :
  https://arxiv.org/html/2508.12358v1
- MAST, pourquoi les systèmes multi-agents échouent (43,8 % de design système, pas de
  déficit de vérification) : https://arxiv.org/html/2503.13657
- Porter/Votta, inspections logicielles : au-delà de 2 relecteurs, zéro défaut de plus :
  https://users.ece.utexas.edu/~perry/education/SE-Intro/porter-tse23.pdf
- Higham, « The MVP is dead, long live the RAT » — ordre RAT → walking skeleton → MVP :
  https://medium.com/hackernoon/the-mvp-is-dead-long-live-the-rat-233d5d16ab02
- Humanizing Work, les 9 patterns de découpage de story :
  https://www.humanizingwork.com/the-humanizing-work-guide-to-splitting-user-stories/
- AgenticFlict, 27,67 % de conflits sur PR agentiques, écrasement silencieux :
  https://arxiv.org/abs/2604.03551
