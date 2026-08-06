# SafeDesk Appliance

Transforme un PC en **terminal SafeDesk** : au demarrage, Docker lance le conteneur
`mobang-desktop` et une session graphique ouvre le bureau KDE en **RDP plein ecran**
(127.0.0.1:3389). Tout est local -> faible latence ; le `/config` du bureau reste
synchronise partout via Syncthing ; son + micro rediriges.

## Materiel de reference
Intel i9-7940X - **NVIDIA RTX 3080** - 64 Go - Samsung 990 EVO Plus **4 To** - Gigabyte X299 - Intel I219-V - audio Realtek ALC1220 + casque USB.
(setup.sh installe le pilote NVIDIA proprietaire ; pour un autre GPU, adapter l etape [3].)

---

## Option A - Installation 100% automatique (recommande)

1. Recupere l ISO **Debian 13 (trixie) netinst** : https://www.debian.org/distrib/netinst -> flashe-la sur une cle USB (Rufus).
2. **Verifie sur cette machine (06/08/2026)** : Windows = disque 0 (Samsung 970, 2 To). Cible = disque 1 (Samsung 990, **4 To**, le plus gros). Cle = WD USB (931 Go, le plus petit -> intacte). L auto-install vise donc le 4 To, Windows reste intact. IMPORTANT : Windows boote en **Legacy/BIOS** -> boote la cle Debian dans le MEME mode (au boot menu Gigabyte F12, choisis l entree USB **SANS prefixe UEFI**) pour un dual-boot propre.
3. Boote la cle. Au menu Debian, touche `TAB` (ou `e`) pour editer la ligne de boot et ajoute :
   ```
   auto=true priority=critical url=https://raw.githubusercontent.com/jeromebarnoinmobang/safedesk/main/appliance/preseed.cfg
   ```
4. Entree. A partir de la, **plus rien a toucher** : partitionnement, install minimale, clonage du repo, puis au 1er boot `setup.sh` s execute (drivers NVIDIA, Docker, image du bureau, kiosque), et reboot -> **le bureau SafeDesk s ouvre seul, plein ecran, avec le son.**

Le tout premier boot est long (telechargements + build de l image). Les logs defilent a l ecran.

## Option B - Manuelle
1. Installe Debian 13 netinst **minimal** (a "Software selection", ne coche que *SSH server* + *standard system utilities*, **aucun bureau**), sur le NVMe 4 To.
2. Au 1er boot, en root :
   ```
   git clone https://github.com/jeromebarnoinmobang/safedesk.git
   cd safedesk/appliance && sudo bash setup.sh && reboot
   ```

---

## Apres install
- **Mot de passe RDP** du bureau : `/etc/safedesk/kiosk.env` (defaut = celui du conteneur). Option B : `SAFEDESK_PASSWORD=xxx sudo -E bash setup.sh`.
- **Mot de passe root** (Option A) : `safedesk-root-change-me` -> **change-le** avec `passwd`.
- **Logs** : `/tmp/startx.log`, `/tmp/frdp.log`, `journalctl -u safedesk-firstboot`, `journalctl -u safedesk-stack`.
- **Dual-boot** : GRUB est pose sur le 4 To et detecte Windows ; choisis l ordre de boot dans le BIOS.

## Debogage 1er boot
- Ecran noir -> `/tmp/frdp.log` (souvent une option xfreerdp a ajuster selon FreeRDP v2/v3).
- Pas de son -> `wpctl status` (PipeWire), verifier le sink par defaut.
- Bureau pas pret -> `docker compose -f /opt/safedesk/docker-compose.yml -f /opt/safedesk/docker-compose.local.yml ps`.