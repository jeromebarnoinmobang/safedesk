# Une configuration stable, récupérable n'importe quand — plan

*Écrit le 28/08/2026, avant le code (décision `c9da28b1`).*

*Objectif de Jérôme : « safedesk a pour objectif d'être un dépôt public, et
l'objectif c'est que je puisse avoir une configuration stable que je peux
récupérer n'importe quand. »*

---

## Le problème, mesuré

Le home `/config` est répliqué **en entier** par Syncthing, avec une liste
d'exclusions qui énumère ce qui ne doit *pas* voyager. Cette approche a échoué, et
elle échouera encore : c'est une liste noire, donc chaque outil nouveau ajoute un
état que personne n'avait prévu.

- 17/08/2026 : 235 fichiers `.sync-conflict-*`, dont 99 dans le profil Claude Desktop.
- 28/08/2026 : **406 conflits actifs**, malgré trois correctifs posés le matin même
  (caches npm/bun/pnpm, `node_modules` applicatifs, bases d'exécution des outils).

Et 15 de ces conflits sont dans `Projects/workbench/.git/` — `index`, `refs/heads`,
`packed-refs`, `config`. Les entrailles d'un dépôt git, écrites simultanément par
deux machines. Ce n'est plus de l'encombrement, c'est un risque de corruption.

### Ce que `/config` contient réellement (mesure du 28/08)

| Entrée | Taille | Nature |
|---|---|---|
| `Projects` | 12 Go | 9 dépôts git — **déjà** synchronisés par git |
| `.config` | 5,3 Go | dont 921 Mo de profil Claude Desktop |
| `.cache` | 5,1 Go | reconstructible (déjà exclu) |
| `.npm`, `.gradle`, `.bun`, `go` | 3,4 Go | caches d'outils (partiellement exclus) |
| `core.*` | **1,8 Go** | vidages mémoire, répliqués pour rien |
| `Desktop`, `.ssh`, `.gnupg`, `.config/safedesk` | < 1 Mo | **la vraie configuration** |

La configuration qui compte pèse moins d'un mégaoctet. Tout le reste est soit
reconstructible, soit déjà versionné ailleurs.

## Le défaut central : Syncthing sert de sauvegarde à ce qui n'en a pas

```
extranet       https://github.com/Auto-Cycling/extranet.git
second-brain   git@github.com:jeromebarnoinmobang/second-brain.git
infra          https://github.com/jeromebarnoinmobang/infra.git
intendant      https://github.com/jeromebarnoinmobang/intendant.git
safedesk       https://github.com/jeromebarnoinmobang/safedesk.git
mcp-poste      AUCUN DISTANT
chantier       AUCUN DISTANT
workbench      /tmp/workbench.bundle
openwork-app   /tmp/openwork-app.bundle
```

**Quatre dépôts sur neuf ne sont récupérables de nulle part.** `workbench` et
`openwork-app` — les forks qui font tourner OpenWork — pointent sur des bundles
dans `/tmp`, effacés au redémarrage.

Leur seule redondance aujourd'hui est la réplication Syncthing. C'est exactement ce
qui rend son retrait effrayant, et c'est aussi la preuve que l'objectif
« récupérable n'importe quand » **n'est pas atteint** : il n'y a pas de source de
vérité, il y a trois copies vivantes qui se battent.

## Le principe

Trois natures de contenu, trois outils — et un seul outil par nature.

| Nature | Outil | Pourquoi |
|---|---|---|
| **Configuration** | git (dépôt public + overlay privé) | versionnée, revue, restaurable à une date |
| **Code** | git (un dépôt par projet) | git EST un outil de synchronisation |
| **Documents** | Syncthing | ce que git fait mal : binaires, gros fichiers, écriture continue |
| **État d'exécution** | *rien* | local par nature : sessions, trousseaux, caches, bases vivantes |

Superposer Syncthing à git est redondant **et** nuisible : les conflits du 28/08
en sont la démonstration.

## Les étapes

### Étape 0 — BLOQUANTE : donner un distant réel aux quatre orphelins

Rien d'autre ne doit bouger avant. Tant que `workbench`, `openwork-app`,
`mcp-poste` et `chantier` n'existent que sur des disques, réduire la réplication
détruirait la seule redondance qu'ils ont.

- `workbench` et `openwork-app` : dépôts **privés** GitHub (ce sont des forks
  portant de la configuration personnelle).
- `mcp-poste`, `chantier` : idem, ou fusion dans un dépôt existant s'ils ne
  méritent pas le leur.
- Vérification : `git -C <dépôt> push` réussit, et `git ls-remote` répond.

### Étape 1 — Inverser la liste d'exclusion en liste blanche

Syncthing sait faire : des motifs `!` d'inclusion, puis un `**` final qui exclut
tout le reste. Rien n'est répliqué s'il n'a pas été nommé.

C'est le cœur du correctif : le défaut passe de « tout, sauf ce qu'on a pensé à
retirer » à « rien, sauf ce qu'on a décidé de partager ». Un outil nouveau
n'ajoute plus jamais de conflit sans qu'on l'ait voulu.

Contenu visé de la liste blanche — la vraie donnée, celle que git gère mal :
`Desktop`, les documents, `.config/safedesk`, les transcriptions `.claude`. Pas
`Projects`, pas les caches, pas les profils.

### Étape 2 — `Projects/` se reconstruit, il ne se réplique plus

Un script versionné lit une liste déclarée de dépôts et les clone ou les met à
jour. La liste vit dans l'**overlay privé** — ce sont les dépôts de Jérôme, pas
ceux du produit.

Conséquence assumée : le travail non commité ne voyage plus d'une machine à
l'autre. C'est une discipline, pas une perte — et c'est ce qui rend l'état
reproductible.

### Étape 3 — Séparer le public du privé (décision `ec13b696`, 13/08)

La décision existe déjà : **overlay privé versionné, pas de fork**. Elle n'a pas
été appliquée. Aujourd'hui le dépôt public contient `voice/` en entier —
`openwork.mobang.fr`, `voice.mobang.fr`, `second-brain.mobang.fr` — et
`start-openwork-stack.sh` délègue à `workbench-docs/run-chaine-dev.sh`, un dépôt
privé.

**Un dépôt public ne doit jamais dépendre d'un dépôt privé** : sinon personne ne
peut s'en servir, et la vitrine est cassée.

- **Public** (`safedesk`) : le bureau. Dockerfile, profils compose (`local`,
  `remote`, `pi5`, `av`, `gpu`), scripts `up-*`, `setup-hote.sh`, `files/`.
- **Privé** (overlay) : `voice/`, les domaines, la liste des dépôts, le `.env`,
  les crochets qui supposent le second-brain.

L'overlay se compose : `docker compose -f … -f overlay/docker-compose.mobang.yml`.
Aucun fork, aucune divergence à fusionner.

## Le critère de réussite

Une machine neuve, sans rien :

```bash
git clone https://github.com/jeromebarnoinmobang/safedesk /opt/safedesk
git clone <overlay-privé> /opt/safedesk-mobang
cd /opt/safedesk && sudo ./scripts/setup-hote.sh && make local
safedesk-depots            # clone les 9 dépôts depuis leurs distants
```

…et l'environnement est là. **C'est ça, « récupérable n'importe quand » :
reconstructible depuis des sources de vérité, pas dépendant de la survie
simultanée de trois disques.**

Ce plan se vérifie de la seule façon qui vaille : en le rejouant sur le Raspberry
Pi, qui doit justement être réinstallé proprement avec une carte SD plus grande.
Si le Pi se reconstruit d'une commande, l'objectif est atteint.
