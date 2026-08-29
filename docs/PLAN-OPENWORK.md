# OpenWork dans SafeDesk — pourquoi rien n'apparaissait, et ce qui change

*Écrit le 26/08/2026 à 11h, avant le code (décision `c9da28b1`). Demande de Jérôme :
« j'ai beau lancer l'interface rien n'apparaît. Résous définitivement sur le PC, et dans
le repository, au redémarrage de safedesk il faut que ce soit fonctionnel. »*

---

## Ce qui était cassé — mesuré, pas supposé

| constat | preuve jouée le 26/08 à 10h50 |
|---|---|
| le front **sert** | `curl -o /dev/null -w %{http_code} http://127.0.0.1:14880` → **200** |
| il pointe sur l'API **publique** | `tr '\0' '\n' < /proc/1391309/environ` → `VITE_OPENWORK_URL=https://openwork-api.mobang.fr` |
| cette API est **morte** | `curl https://openwork-api.mobang.fr/health` → **502** |
| l'API **locale** est vivante | `curl http://127.0.0.1:14877/health` → `{"ok":true,"opencodeVersion":"1.18.18"}` |
| opencode du VPS est vivant | `curl -u … http://127.0.0.1:14098/global/health` → `{"healthy":true,"version":"0.0.0-safework-server-202608251700"}` |
| le tunnel **inverse** est mort | `pgrep -af "ssh.*-R"` → rien |
| la relance du 25/08 a échoué | `tmp/logs/front.log` → `Error: Port 14880 is already in use` |

**La chaîne était donc entière SAUF un maillon : l'adresse que le front appelle.**
Le navigateur chargeait la page, tapait sur une URL en 502, et n'affichait rien.

## Les trois fautes, par ordre de gravité

### 1. Le contrôle de santé mentait

`openwork-poste` testait `curl -sf http://127.0.0.1:14880`. Un front **périmé, pointé sur
une API morte, rend 200**. Le lanceur voyait donc « tout va bien » et ne relançait jamais.

> C'est le mode de panne que ce poste combat partout ailleurs : *une panne franche
> transformée en panne muette*. Ici elle avait duré plus de 24 h.

### 2. La relance ne pouvait pas aboutir

Le 25/08 à 19:01, `run-chaine-dev.sh` a été rejoué avec un repli d'API tout neuf. Il a
échoué sur `Port 14880 is already in use` — l'ancien vite tenait encore le port, et le
script ne le tuait pas. **Le correctif écrit ce soir-là n'a jamais pris effet.**

### 3. Le bureau dépendait d'Internet pour se parler à lui-même

Le front (127.0.0.1:14880) appelait `https://openwork-api.mobang.fr`, qui repart vers le
VPS, redescend par un tunnel SSH inverse, et revient sur **127.0.0.1:14877** — la même
machine, deux numéros de port plus loin. Un aller-retour par Internet pour joindre son
propre voisin. Le jour où la route publique tombe, le bureau tombe avec elle.

---

## Ce qu'on met à la place

### A. Le front du bureau parle à l'API **locale**. Toujours.

Plus de repli conditionnel, plus d'« auto ». Le poste ne meurt plus parce que le VPS
tousse. C'est la seule règle qui rende le bureau **autonome**, et l'autonomie est la
raison d'être de SafeDesk.

### B. Le contrôle de santé cesse de mentir — il **mesure** au lieu de **déclarer**

L'API que le front appelle n'est plus lue dans un fichier qu'on a écrit (qui dérive),
mais dans **l'environnement du processus vite vivant** :

```bash
tr '\0' '\n' < /proc/$PID_VITE/environ | sed -n 's/^VITE_OPENWORK_URL=//p'
```

C'est la vérité, pas une intention. Le contrôle devient :

> le front rend 200 **ET** l'API qu'il appelle réellement rend 200.

Un front qui pointe sur une adresse morte est désormais **détecté et remplacé**.

### C. La chaîne devient un **service supervisé**, pas un effet de bord de l'icône

| avant | après |
|---|---|
| l'icône démarrait la chaîne | `safedesk-openwork` (s6) la monte et la **garde** |
| rien ne repartait au redémarrage | s6 démarre le service à chaque boot du conteneur |
| une mort silencieuse durait 24 h | boucle de contrôle toutes les 30 s, réparation automatique |
| l'icône ne savait pas quoi faire | l'icône **ouvre une fenêtre**, rien d'autre |

### D. Un port occupé ne peut plus faire échouer une relance

On tue par **PID lu dans `ss -lntp`**, jamais par `pkill -f` sur un motif — un `pkill -f`
qui figure dans sa propre ligne de commande **se tue lui-même** (déjà mesuré deux fois,
`exit 144`, cf. commentaire de `run-chaine-dev.sh`).

### E. Le téléphone n'est pas sacrifié — il est **séparé**

Le front du bureau et celui du téléphone ne peuvent pas partager une seule adresse d'API :
`127.0.0.1:14877` ne veut rien dire depuis un téléphone. Donc **deux fronts** :

| front | port | API appelée | pour qui |
|---|---|---|---|
| bureau | 14880 | `http://127.0.0.1:14877` | l'écran de SafeDesk |
| téléphone | 14881 | `https://openwork-api.mobang.fr` | `openwork.mobang.fr` via le tunnel inverse |

Le tunnel inverse remonte désormais **14881** (et non 14880) vers le VPS.
**Une panne du volet téléphone ne bloque jamais le bureau** : les maillons du bureau sont
assurés d'abord, ceux du téléphone ensuite, et leur échec est journalisé, pas fatal.

Coût mesuré : un second vite, ~260 Mo. La machine a 46 Go disponibles.

---

## Où ça vit — la règle qui évite la dérive

Tout ce qui doit survivre à une reconstruction va **dans le dépôt `safedesk`** :

| fichier | rôle |
|---|---|
| `files/usr/local/bin/openwork-chaine` | **le** script de chaîne (état / assurer / relancer / stop) |
| `files/usr/local/bin/openwork-poste` | le lanceur de l'icône — n'ouvre qu'une fenêtre |
| `files/custom-services.d/safedesk-openwork` | le service s6 supervisé |
| `files/usr/share/applications/OpenWork.desktop` | l'icône, posée par `desktop-shortcuts` |
| `Dockerfile` | les `COPY` correspondants |
| `docker-compose.local.yml` | les montages, pour qu'une **recréation** suffise (sans rebuild) |

`safework-docs/run-chaine-dev.sh` devient un **renvoi** vers le script canonique : deux
copies du même script sont une source de dérive, et c'est exactement ce qui a permis
qu'un correctif écrit le 25/08 ne serve à rien.

---

## Ce que ce plan ne fait pas, volontairement

- **On ne passe pas vite en build statique.** Ce serait plus robuste et moins cher, mais
  c'est une refonte ; la demande est de réparer.
- **On ne touche pas au code de `safework`.** Le défaut n'est pas dans l'application.
- **On ne redémarre pas le conteneur.** Les fichiers sont posés à la fois dans le dépôt
  *et* dans le conteneur vivant, et le service est démarré à la main : le résultat est
  vrai maintenant **et** au prochain démarrage.

## Comment on saura que c'est réparé

```bash
openwork-chaine etat     # code retour 0, quatre maillons OK
```

et, la seule preuve qui compte pour Jérôme : **l'icône ouvre une fenêtre où quelque chose
s'affiche.**
