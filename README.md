# SafeDesk

**Un bureau Linux complet, identique en local et depuis le web, pour rendre l informatique
sure et accessible a ceux qu elle depasse ou qu elle met en danger.**

SafeDesk est un environnement de bureau KDE conteneurise que vous lancez **sur votre machine**
ou que vous **streamez depuis un serveur** — meme image, meme dossier personnel, meme reglages.
Vous fermez votre ordinateur, vous rouvrez le bureau depuis un navigateur ailleurs : tout est la.

## Pourquoi

Ce projet est ne de deux arnaques bien reelles : une personne agee piegee par une fausse fenetre
de "support technique" qui a fini par donner sa carte bancaire, et un faux artisan aux excellents
avis en ligne. Le constat : les gens malhonnetes ont de meilleurs outils que leurs victimes.

L idee n est pas d enfermer l utilisateur, mais de lui presenter une surface **adaptee, guidee
et defendue** — *une cloture contre les loups, pas une cage*. Le bureau cache la complexite du
systeme, et un assistant l aide et agit a sa place quand il le demande.

## Ce que ca fait aujourd hui

- **Bureau KDE Plasma complet** streame dans un onglet (WebRTC), image figee par digest.
- **Local ou distant, au choix** : en local il ne consomme rien sur le serveur ; a distance il
  reste disponible machine eteinte, derriere HTTPS et authentification.
- **Dossier personnel synchronise** entre les deux (Syncthing) : reglages, fichiers, profils
  de navigateur suivent l utilisateur.
- **Detection automatique du GPU** : accelere le rendu quand la machine le permet, retombe
  proprement en rendu logiciel sinon — sans configuration.
- **Outils** : Chromium, VS Code, GitHub CLI, Node, git.
- **Composants proprietaires optionnels**, desactives par defaut : Google Chrome et Claude
  Desktop s installent uniquement si vous le demandez (`INSTALL_CHROME=true` /
  `INSTALL_CLAUDE=true` dans `.env`). L image par defaut ne contient que du logiciel libre.

## Demarrage rapide

Prerequis : Docker et Docker Compose.

```bash
git clone https://github.com/<vous>/safedesk.git && cd safedesk
cp .env.example .env      # definissez au moins DESKTOP_PASSWORD
./scripts/up-local.sh     # Windows : powershell -ExecutionPolicy Bypass -File scripts\up-local.ps1
```

Le bureau repond sur <http://localhost:3000> (publie sur la boucle locale uniquement).

### Deploiement distant (streame)

Adaptez `docker-compose.remote.yml` a votre reverse proxy, pointez le DNS du sous-domaine
vers le serveur, puis :

```bash
docker compose -f docker-compose.yml -f docker-compose.remote.yml up -d
```

**N exposez jamais ce bureau sans HTTPS ni authentification** : il donne acces a une session
complete, avec les comptes qui y sont connectes.

## Architecture

| Fichier | Role |
|---|---|
| `docker-compose.yml` | Base commune : bureau + sidecar de synchronisation |
| `docker-compose.local.yml` | Publie le bureau sur la boucle locale |
| `docker-compose.remote.yml` | Route derriere un reverse proxy (HTTPS + auth) |
| `docker-compose.gpu-wsl.yml` | GPU sous Windows/WSL2 (Direct3D 12) |
| `docker-compose.gpu-dri.yml` | GPU sous Linux natif (`/dev/dri`) |
| `Dockerfile` | Image : bureau + navigateurs + outils |
| `scripts/up-local.*` | Detection GPU puis lancement |
| `chromium.d/zz-*` | Profils de rendu injectes dans les navigateurs |

Le profil de rendu retenu est monte sur `/etc/chromium.d/zz-render` : Chromium **et** Chrome en
heritent, sans duplication de configuration.

## Detection du GPU

| Detecte dans un conteneur | Profil |
|---|---|
| `/dev/dxg` + `libd3d12.so` (Windows/WSL2) | `zz-gpu-wsl` |
| `/dev/dri` (Linux natif) | `zz-gpu-dri` |
| rien | `zz-no-gpu` (rendu logiciel) |

**Piege verifie** : `nvidia-smi` qui repond ne prouve rien sur le rendu. Sous WSL2 le GPU est
expose en calcul ; l OpenGL passe par les bibliotheques WSL montees et le pilote Mesa **d3d12**.
Sans elles, ou en forcant `--use-gl=egl`, le processus GPU des navigateurs **quitte a l initialisation**
et les fenetres deviennent blanches. Ne forcez pas `--use-gl` : seul `egl-angle` est autorise.

Verifier l acceleration reelle :

```bash
docker exec -u 0 <conteneur> apt-get install -y mesa-utils
docker exec <conteneur> sh -c 'DISPLAY=:1 LD_LIBRARY_PATH=/usr/lib/wsl/lib GALLIUM_DRIVER=d3d12 glxinfo -B'
# attendu : "Accelerated: yes"
```

## Synchronisation du dossier personnel

Un sidecar Syncthing monte le volume `/config` sur `/sync/home` et le replique entre les hotes
(dossier `desktop-home`, bidirectionnel, fichiers volatils exclus).

- **Un seul bureau actif a la fois** : la convergence se fait au moment ou vous basculez.
- Sont synchronises : reglages, fichiers, profils. Ne le sont pas : les paquets systeme
  (ils vivent dans l image) et les caches.
- Si le port pair-a-pair est filtre par le reseau, faites passer la synchronisation par un
  reseau prive (Tailscale/Headscale, WireGuard) plutot que par les relais publics.

**Note** : l image officielle Syncthing tourne en UID 1000 et n utilise pas `PUID`/`PGID` ;
son volume de configuration doit appartenir a `1000:1000`, sinon elle ne peut pas ecrire son
certificat et redemarre en boucle.

## Navigateurs et compte Google

Chromium ne peut pas connecter un compte Google **au navigateur** : depuis le 15 mars 2021,
Google reserve le jeton de synchronisation aux versions officielles de Chrome. La fenetre de
connexion reste blanche — ce n est pas un defaut de ce projet. Google Chrome officiel est donc
fourni dans l image pour ceux qui veulent cette synchronisation.

## Securite

- Le bureau donne acces a une **session complete** : traitez son mot de passe comme un secret fort.
- Le dossier personnel etant replique, les sessions et mots de passe enregistres dans les
  navigateurs le sont aussi. Choisissez en consequence ce que vous connectez.
- `.env` n est jamais versionne. Aucun secret n est stocke dans ce depot.

## Feuille de route

- Pont **MCP** entre l assistant et le bureau : percevoir l ecran et agir, avec confirmation
  obligatoire sur les actions irreversibles.
- **Assistant vocal** (reconnaissance et synthese) branche sur ce pont.
- **Surface adaptee** : profils (senior, enfant, debutant), filtrage anti-arnaque, garde-fous
  en langage clair, mode kiosque. Protegér sans enfermer : consenti, transparent, toujours une sortie.
- Declinaison **telephone** (Plasma Mobile est convergent) sur le meme dossier personnel.

## Licence

[AGPL-3.0](LICENSE). Si vous proposez ce bureau comme service en ligne, vous devez publier
vos modifications.