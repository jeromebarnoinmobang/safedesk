# Ramener opencode dans SafeDesk — plan

*Écrit le 27/08/2026 à 13h35, avant le code (décision `c9da28b1`).*
*Direction de Jérôme : « si le fonctionnement normal c'est de faire tourner opencode
sur le poste local, ben alors on va dans ce sens. »*

---

## Ce qui a déclenché ce plan

Jérôme : *« je veux que openwork soit une alternative à claude desktop, donc doit
avoir les mêmes capacités d'agir sur mon poste physique. »*

Et sa contestation, qui était juste : *« opencode ne fonctionne pas comme tu le dis,
parce qu'on le selfhost mais normalement c'est un serveur du SaaS. »*

**Preuve — `safework/apps/server/src/managed-opencode.ts:158` :**

```ts
const child = spawn(options.bin?.trim() || "opencode",
  ["serve", "--hostname", hostname, "--port", String(port), "--cors", "*"], …)
```

Le client openwork **lance lui-même** `opencode serve`, en processus enfant, avec tout
un `engine-pool` autour (plusieurs moteurs, remplacement à chaud). Le moteur est donc
**local par conception**, et le SaaS (le Den) porte les comptes et le cloud — pas le
moteur. C'est l'architecture de Claude Desktop : **modèle distant, outils locaux.**

**Notre installation dévie.** Pas le besoin de Jérôme.

---

## LA DÉCISION QU'ON REVISITE, ET POURQUOI ON A LE DROIT

Le 25/08, opencode a été sorti de SafeDesk pour une raison précise et bonne : le 24/08
à 09:13 il y est mort d'un `PATH` manquant, et **personne ne l'a su pendant 24 h**.

> Mais ce n'était pas un défaut de l'endroit. C'était une **absence de supervision**.

Elle existe depuis le 26/08 : `safedesk-safework` (s6) constate et répare toutes les
30 s, et a remonté une chaîne entièrement démontée **en 15 secondes**, sans
intervention.

**Le déménagement traitait le symptôme. La supervision traite la cause.**

---

## CE QUE L'ENQUÊTE DOIT TRANCHER AVANT QU'ON TOUCHE À QUOI QUE CE SOIT

Quatre angles, avec un sceptique par constat (workflow `wf_3a3e0b9b`) :

1. **Le moteur embarqué** — le binaire est-il attendu sur le `PATH`, ou fourni par le
   paquet ? `embedded.ts:205` lit `OPENWORK_OPENCODE_BIN`.
2. **Le Den** — provisionne-t-il un moteur (`PROVISIONER_MODE`, `rem_`), ou seulement
   des comptes ? Si oui, le mode « moteur distant » existe et a ses règles.
3. **Un pont d'outils** — existe-t-il un moyen d'exécuter les outils ailleurs que dans
   le processus opencode ? Si oui, tout ce plan tombe et il y a mieux à faire.
4. **Claude Desktop** — où passe exactement la frontière modèle/outils, pour comparer
   ce qui est comparable.

**Tant que ces quatre points ne sont pas rendus, on n'exécute rien.** Une décision du
25/08 ne se défait pas sur un seul `grep` — c'est la leçon des deux derniers jours.

---

## Si l'enquête confirme : ce qu'il y a à faire

### C1 — opencode dans SafeDesk, supervisé dès le premier jour

Le binaire est déjà là (`safework-server/packages/opencode/dist/opencode-linux-x64/bin/`,
compilé ce matin), `claude` aussi (2.1.233). Service s6 sur le modèle de
`safedesk-safework`, et **le contrôle de santé teste une inférence, pas un `/health`** —
c'est le 25/08 qui l'a appris : un serveur peut rendre 200 avec une configuration morte.

### C2 — la configuration du poste

`opencode.jsonc` local : le MCP `second-brain`, le provider `claude-code`, et **le MCP
`poste` redevient légitime** (il pilote X11 — il y a un écran ici, c'était la raison de
son absence côté VPS).

### C3 — le graphe suit

`OPENCODE_FLUX` + le dossier `flux/` sur le poste. C'est l'arbitrage du 27/08 :
OpenWork = régime chantier, quel que soit l'endroit. `chantier.json` se régénère depuis
le Go, comme pour le VPS.

### C4 — opencode du VPS est RETIRÉ

**Tranché par Jérôme le 27/08 à 13h35 : « on va retirer opencode du VPS, il n'a plus
de sens. »** Un seul moteur, sur le poste, là où sont les fichiers.

**MAIS L'ORDRE N'EST PAS CELUI DE LA PHRASE, ET C'EST LE POINT LE PLUS IMPORTANT DE CE
PLAN.**

Aujourd'hui la chaîne OpenWork ne tient QUE par opencode du VPS : `safework-chaine`
ouvre un tunnel vers lui, et le serveur openwork ne parle qu'à ça. Le retirer d'abord,
c'est se retrouver sans OpenWork du tout, avec un moteur local qui n'existe pas encore.

Séquence, et on ne l'inverse pas :

| | | on ne passe à la suite que si |
|---|---|---|
| 1 | opencode local dans SafeDesk, supervisé | une **inférence réelle** aboutit, pas un `/health` |
| 2 | `safework-chaine` bascule sur lui | les 5 maillons OK, `etat` rend 0 |
| 3 | épreuve de bout en bout | outils, permissions, graphe franchi, et une tâche réelle sur `/config/Projects` |
| 4 | **alors** on retire le VPS | et pas avant |

Vérifié le 27/08 : **rien en dehors de la chaîne OpenWork ne dépend d'opencode-vps.**
Ni `chantier`, ni `intendant`, ni la sonde. Les seuls fichiers qui le nomment sont ceux
de la chaîne et son propre déploiement.

Ce qu'on perd en le retirant, et il faut le dire : **le téléphone n'a plus de cerveau
quand le poste est éteint.** C'est le prix assumé du choix — les fichiers sont sur le
poste, donc le moteur aussi.

Le retrait se fera en gardant l'image (`docker compose down` sans `--rmi`) : réversible
en une commande tant que Jérôme n'a pas vécu quelques jours avec.

### C5 — ce qu'il ne faut pas perdre en chemin

- les **sessions** (`opencode-safework-server.db`) vivent dans un volume côté VPS ; côté poste
  elles iront dans `/config`, qui persiste ;
- les **clés de déploiement** posées ce matin sont sur le VPS. Si le travail passe sur
  le poste, les dépôts y sont **déjà**, en clair, avec les vrais remotes — plus besoin de
  clés du tout pour ce cas ;
- l'**espace de travail** : sur le poste, ce sera `/config/Projects`, c'est-à-dire la
  vraie copie de travail de Jérôme. Voir ci-dessous.

---

## LE POINT QUI N'EST PAS TECHNIQUE

Sur le VPS, l'agent travaille sur des **clones**, dans un conteneur isolé. Sur le poste,
il écrira dans `/config/Projects` — **les fichiers de Jérôme**.

C'est ce que notait la mémoire `51e617b5` du 20/08 : *« le cerveau du chantier est un
AGENT avec accès fichiers — risque réel ».*

Trois choses ont changé depuis, et elles sont mesurées :

| garde | état |
|---|---|
| la fenêtre de permission | **fonctionne** — prouvé le 27/08, une écriture hors espace bloquée puis refusée |
| `cadrer` et ses impératifs de domaine | **en place** — bloque déjà `/etc/mobang`, `.age-key`, `/secrets` |
| git | le vrai filet — **à condition que tout soit commité** |

**Préalable non négociable :** commiter ce qui traîne (`intendant/interne/evaluer`,
`interne/retitre`, `main.go`). Ouvrir `/config/Projects` à un agent pendant qu'il s'y
trouve du travail qui n'existe nulle part ailleurs, c'est enlever le filet avant de
monter sur le fil.

À élargir dans `imperatifs.json` : `.config/safedesk`, `.ssh`, `.claude`.
