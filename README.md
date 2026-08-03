# mobang-desktop — bureau KDE portable (local **ou** streamé depuis le VPS)

La « brique OS » du projet : un bureau **KDE conteneurisé**, reproductible, qu'on lance :
- **en local** (ta machine calcule, **zéro charge sur le VPS**), ou
- **sur mobang (VPS)** et **streamé dans le navigateur** (pour vieux PC / accès distant).

Même image → même bureau. L'état vit dans un volume. Tout est déclaratif → **reproductible**
(`git clone` + `make` = même environnement partout).

---

## « Est-ce que le local décharge le VPS ? » → OUI
Le conteneur s'exécute **là où tu le lances**, jamais aux deux endroits :
- **local** → ton CPU/RAM bossent, le VPS n'est **pas** sollicité (hors sync du home, négligeable). Marche hors-ligne.
- **VPS** → le VPS bosse et streame.

C'est **l'un OU l'autre**. On ne streame depuis le VPS **que** quand la machine cible est trop faible
(vieux PC = juste un navigateur). Machine costaude = local, VPS libre.

---

## Prérequis
- Docker + Docker Compose.
- (VPS uniquement) Traefik déjà en place — c'est ton cas sur mobang.

## Lancer en LOCAL
```bash
cp .env.example .env        # renseigne user/mot de passe/TZ
make local                  # = docker compose ... up -d
# → http://localhost:3000   (bureau KDE dans ton navigateur)
```

## Déployer sur le VPS (mobang), streamé + derrière Traefik
```bash
# renseigne DESKTOP_DOMAIN + DESKTOP_BASICAUTH dans .env
make deploy
# → https://$DESKTOP_DOMAIN  (HTTPS + auth obligatoires)
```

---

## ⚠️ Sécurité — non négociable
Un bureau accessible = un **accès complet à une machine**. Sur le VPS, il **doit** être :
- en **HTTPS** (Traefik s'en charge),
- derrière une **authentification** (basic auth / middleware) — **jamais exposé nu**.
Voir `docker-compose.vps.yml`.

## Reproductibilité
- Image **épinglée** (tag **+ digest `@sha256:`**) — pas de `:latest` en prod.
- Tout l'état dans le volume `config` (home KDE). Rien de durable dans le conteneur.
- Config par `.env`. Aucune étape manuelle cachée.

## Feuille de route (les briques, dans l'ordre)
1. [x] **Base** : bureau KDE conteneurisé, local + VPS streamé — *ce repo*.
2. [ ] **Pont MCP** : exposer les capacités du bureau à un LLM (agnostique).
3. [ ] **Assistant voix** (STT/TTS) branché sur le pont.
4. [ ] **Surface adaptée + garde-fous** (profils, anti-arnaque, kiosk).
5. [ ] **Sync du home** local ↔ VPS.


## Home sync (Syncthing via tailnet)

Chaque hote lance un sidecar Syncthing (`home-sync`) qui monte le volume `/config`
du bureau sur `/sync/home` et le replique. Dossier partage `desktop-home` (sendreceive),
`.stignore` pour les fichiers volatils (cache, sockets, locks, X auth, caches navigateur).

**Transport : tailnet headscale, direct** (le port P2P public 22000 est bloque en sortie
par le reseau local). Cote local, l'adresse du device VPS = `tcp://100.64.0.1:22000`.

Piege : l'image officielle `syncthing/syncthing` tourne en **UID 1000** et n'utilise PAS
`PUID/PGID` -> le volume de config Syncthing doit etre `chown 1000:1000`, sinon crash
(`permission denied` sur cert.pem).

## Modele d'usage

- Un seul bureau actif a la fois (local **ou** VPS) -> converge au switch (~10 s).
- Synchronise = le HOME (`/config`). Pas synchronises = paquets systeme (apt) ni volatils.

## Rendu graphique : detection automatique du GPU

`scripts/up-local.ps1` (Windows) et `scripts/up-local.sh` (Linux/macOS) sondent la
capacite de rendu **dans un conteneur** avant de lancer, puis choisissent le profil :

| Detection | Profil | Override compose |
|---|---|---|
| `/dev/dxg` + `libd3d12.so` (Windows/WSL2) | `zz-gpu-wsl` | `docker-compose.gpu-wsl.yml` |
| `/dev/dri` (Linux natif) | `zz-gpu-dri` | `docker-compose.gpu-dri.yml` |
| rien | `zz-no-gpu` | aucun (rendu logiciel) |

Le profil est monte sur `/etc/chromium.d/zz-render` via la variable `RENDER_PROFILE`.

**Piege verifie** : `nvidia-smi` qui repond ne prouve RIEN sur le rendu. Sur WSL2, le GPU
est expose en compute (CUDA) via `/dev/dxg` ; l'OpenGL passe par les libs WSL montees
(`/usr/lib/wsl`) et le driver **Mesa gallium d3d12**. Sans elles, ou en forcant `--use-gl=egl`,
le process GPU de Chromium **quitte a l'initialisation** et les fenetres deviennent blanches.
Ne pas forcer `--use-gl` : Chromium n'autorise que `egl-angle`.

Verification (temporaire, dans le conteneur) :

```bash
docker exec -u 0 mobang-desktop apt-get install -y mesa-utils
docker exec mobang-desktop sh -c 'DISPLAY=:1 LD_LIBRARY_PATH=/usr/lib/wsl/lib GALLIUM_DRIVER=d3d12 glxinfo -B'
# attendu : OpenGL renderer string: D3D12 (NVIDIA ...) / Accelerated: yes
```

Le VPS n'a pas de carte : il reste en `zz-no-gpu` (`make deploy` force ce profil).

## Navigateur : Google Chrome officiel

Chromium (build non-brande) **ne peut pas** connecter un compte Google au navigateur :
depuis le 15/03/2021 Google reserve le jeton OAuth de sync a Chrome officiel. La popup
de connexion part en cul-de-sac et reste blanche — ce n'est pas un bug de cette install.

L'image est donc construite localement (`Dockerfile`) a partir de webtop KDE + le paquet
`google-chrome-stable` officiel. Chrome est lance par `/usr/local/bin/wrapped-google-chrome`,
qui source le meme profil de rendu que Chromium (`/etc/chromium.d/zz-render`) : il herite
donc automatiquement du GPU ou du rendu logiciel selon la machine.

`docker compose up` construit l'image si besoin (`image: mobang/desktop:kde`).
Le profil Chrome vit dans `/config` -> il est repliqué local <-> VPS par Syncthing.

## Claude Desktop (beta Linux)

Le bouton de telechargement de claude.com affiche "Non disponible pour Linux" : c'est une
mauvaise detection de plateforme. Le paquet **existe** (beta) et fournit Chat, Cowork et Code.
Il est installe dans l'image depuis le depot apt officiel Anthropic ; la cle de signature est
**verifiee par empreinte** dans le Dockerfile (`31DDDE24...1A7ECACE`) -> le build echoue si elle
ne correspond pas.

Prerequis : Debian 12+ / Ubuntu 22.04+, amd64 ou arm64 (l'image est Debian 13 : OK).

Absent de la beta Linux (a savoir pour la brique pont MCP) :
- **Computer Use** (controle ecran/apps) : indisponible sur Linux.
- **Dictee vocale** : indisponible dans l'app (dispo via la CLI).