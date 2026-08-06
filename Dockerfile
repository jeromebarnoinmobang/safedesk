# SafeDesk — bureau KDE conteneurise.
#
# Par defaut l image ne contient que du logiciel libre. Les composants proprietaires
# (Google Chrome, Claude Desktop) sont OPTIONNELS et desactives : activez-les
# explicitement si vous en avez l usage.
#
#   docker compose build --build-arg INSTALL_CHROME=true --build-arg INSTALL_CLAUDE=true
#   ou, via .env :  INSTALL_CHROME=true / INSTALL_CLAUDE=true
FROM lscr.io/linuxserver/webtop:debian-kde@sha256:2c69b3325b177713ac388fd8c0b95589bc537e938c5ff6e7a5435887fc35d0f6

ARG INSTALL_CHROME=false
ARG INSTALL_CLAUDE=false
ARG INSTALL_SUNSHINE=false
ARG INSTALL_FORGE=false

# --- Outils de travail (libres) : Node, git, GitHub CLI, VS Code ---
# NB : jamais de commentaire inline dans un RUN multi-lignes — Docker fusionne les lignes
#      et tout ce qui suit un # serait ignore SILENCIEUSEMENT.
# npm/npx sont fournis par le paquet nodejs (NodeSource) : ne pas installer npm (conflit).
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl gnupg; \
    apt-get install -y --no-install-recommends nodejs git; \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg; \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg; \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list; \
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
      | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg; \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
      > /etc/apt/sources.list.d/vscode.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends gh code; \
    rm -rf /var/lib/apt/lists/*

# --- OPTIONNEL : Google Chrome (proprietaire) ---
# Chromium ne peut pas connecter un compte Google au navigateur : depuis le 15/03/2021
# Google reserve le jeton de synchronisation aux versions officielles de Chrome.
RUN set -eux; \
    if [ "$INSTALL_CHROME" = "true" ]; then \
      apt-get update; \
      curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
        | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg; \
      echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
        > /etc/apt/sources.list.d/google-chrome.list; \
      apt-get update; \
      apt-get install -y --no-install-recommends google-chrome-stable; \
      rm -rf /var/lib/apt/lists/*; \
    fi

# --- OPTIONNEL : Claude Desktop (proprietaire, beta Linux) ---
# La cle du depot est verifiee par empreinte : le build ECHOUE si elle ne correspond pas.
RUN set -eux; \
    if [ "$INSTALL_CLAUDE" = "true" ]; then \
      apt-get update; \
      curl -fsSLo /usr/share/keyrings/claude-desktop-archive-keyring.asc \
        https://downloads.claude.ai/claude-desktop/key.asc; \
      gpg --show-keys --with-colons /usr/share/keyrings/claude-desktop-archive-keyring.asc \
        | grep -q '31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE'; \
      echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main" \
        > /etc/apt/sources.list.d/claude-desktop.list; \
      apt-get update; \
      apt-get install -y --no-install-recommends claude-desktop; \
      rm -rf /var/lib/apt/lists/*; \
    fi


# --- OPTIONNEL : Sunshine (GPL) — recepteur du client Moonlight (acces telephone/tablette) ---
# Capture la MEME session que le navigateur (DISPLAY :1). A n exposer que sur un reseau
# prive (VPN / tailnet) : voir docker-compose.phone.yml.
RUN set -eux; \
    if [ "$INSTALL_SUNSHINE" = "true" ]; then \
      apt-get update; \
      curl -fsSLo /tmp/sunshine.deb \
        https://github.com/LizardByte/Sunshine/releases/download/v2026.516.143833/sunshine-debian-trixie-amd64.deb; \
      apt-get install -y --no-install-recommends /tmp/sunshine.deb; \
      rm -f /tmp/sunshine.deb; rm -rf /var/lib/apt/lists/*; \
    fi

# Service s6 : demarre Sunshine quand la session graphique est prete (inerte si non installe)
COPY files/custom-services.d/sunshine /custom-services.d/sunshine

# --- OPTIONNEL : forge APK in-desktop (JDK + SDK Android + gradle) ---
# Permet de construire et signer les applications SafeDesk DEPUIS le bureau.
ENV ANDROID_HOME=/opt/android-sdk
ENV PATH=$PATH:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:/opt/gradle/bin
RUN set -eux; \
    if [ "$INSTALL_FORGE" = "true" ]; then \
      apt-get update; \
      mkdir -p /usr/share/man/man1; \
      apt-get install -y --no-install-recommends openjdk-21-jdk-headless unzip; \
      curl -fsSLo /tmp/ct.zip "https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip"; \
      mkdir -p "$ANDROID_HOME/cmdline-tools"; \
      unzip -q /tmp/ct.zip -d "$ANDROID_HOME/cmdline-tools"; \
      mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"; \
      rm /tmp/ct.zip; \
      yes | sdkmanager --licenses >/dev/null; \
      sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"; \
      curl -fsSLo /tmp/gradle.zip "https://services.gradle.org/distributions/gradle-8.9-bin.zip"; \
      unzip -q /tmp/gradle.zip -d /opt; mv /opt/gradle-8.9 /opt/gradle; rm /tmp/gradle.zip; \
      chmod -R a+rX "$ANDROID_HOME" /opt/gradle; \
      rm -rf /var/lib/apt/lists/*; \
    fi

COPY files/usr/local/bin/safedesk-forge /usr/local/bin/safedesk-forge
COPY files/usr/share/applications/safedesk-forge.desktop /usr/share/applications/safedesk-forge.desktop
RUN chmod +x /usr/local/bin/safedesk-forge

# QR d onboarding affiches depuis le bureau (icone "QR telephone")
RUN set -eux; apt-get update; \
    apt-get install -y --no-install-recommends qrencode zip espeak-ng; \
    apt-get install -y --no-install-recommends libttspico-utils || true; \
    rm -rf /var/lib/apt/lists/*
COPY files/usr/local/bin/safedesk-qr /usr/local/bin/safedesk-qr
COPY files/usr/share/applications/safedesk-qr.desktop /usr/share/applications/safedesk-qr.desktop
COPY files/custom-services.d/desktop-shortcuts /custom-services.d/desktop-shortcuts
RUN chmod +x /usr/local/bin/safedesk-qr

# Lanceur d applications (tuiles de l accueil telephone) : localhost:3010,
# expose via nginx sous /safedesk/ -> herite de l auth basique du serveur.
COPY files/usr/local/bin/safedesk-launcher /usr/local/bin/safedesk-launcher
COPY files/custom-services.d/safedesk-launcher /custom-services.d/safedesk-launcher
COPY files/custom-services.d/safedesk-nginx /custom-services.d/safedesk-nginx
RUN chmod +x /usr/local/bin/safedesk-launcher
# Lanceur maison : fait heriter Chrome du profil de rendu detecte (/etc/chromium.d/zz-render)
COPY files/usr/local/bin/wrapped-google-chrome /usr/local/bin/wrapped-google-chrome
RUN set -eux; \
    chmod +x /usr/local/bin/wrapped-google-chrome; \
    if [ -f /usr/share/applications/google-chrome.desktop ]; then \
      sed -i 's|^Exec=/usr/bin/google-chrome-stable|Exec=/usr/local/bin/wrapped-google-chrome|' \
        /usr/share/applications/google-chrome.desktop; \
    fi
# --- SafeDesk : correctifs finaux (en fin de Dockerfile pour PRESERVER le cache des couches lourdes) ---
# Audio : sinks output/input captes par Selkies (sinon PulseAudio => auto_null => aucun son)
RUN printf '\n### SafeDesk audio (sinks captes par Selkies)\nload-module module-null-sink sink_name=output sink_properties=device.description=output rate=48000 channels=2\nload-module module-null-sink sink_name=input sink_properties=device.description=input rate=44100 channels=2\nset-default-sink output\nset-default-source output.monitor\n' >> /etc/pulse/default.pa
# Claude Desktop (si installe) : handler claude:// (retour login OAuth) + lancement sans trousseau
RUN set -eux; \
    if [ "$INSTALL_CLAUDE" = "true" ]; then \
      apt-get update; \
      apt-get install -y --no-install-recommends desktop-file-utils; \
      rm -rf /var/lib/apt/lists/*; \
      update-desktop-database /usr/share/applications || true; \
      if [ -e /usr/bin/claude-desktop ]; then \
        rm -f /usr/bin/claude-desktop; \
        printf '#!/bin/bash\nexec /usr/lib/claude-desktop/claude-desktop --password-store=basic "$@"\n' > /usr/bin/claude-desktop; \
        chmod +x /usr/bin/claude-desktop; \
      fi; \
    fi

# --- Acces RDP local basse latence (xrdp + KDE) ; port 3389 publie seulement en local ---
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends xrdp xorgxrdp dbus-x11; \
    rm -rf /var/lib/apt/lists/*; \
    adduser xrdp ssl-cert || true
COPY files/etc/xrdp/startwm.sh /etc/xrdp/startwm.sh
COPY files/custom-services.d/xrdp /custom-services.d/xrdp
RUN chmod +x /etc/xrdp/startwm.sh /custom-services.d/xrdp

# --- Audio RDP : module xrdp pre-compile + service de routage auto (toutes apps, RDP<->navigateur) ---
COPY files/usr/lib/pulse-17.0+dfsg1/modules/module-xrdp-sink.so /usr/lib/pulse-17.0+dfsg1/modules/module-xrdp-sink.so
COPY files/usr/lib/pulse-17.0+dfsg1/modules/module-xrdp-source.so /usr/lib/pulse-17.0+dfsg1/modules/module-xrdp-source.so
COPY files/custom-services.d/safedesk-rdp-audio /custom-services.d/safedesk-rdp-audio
RUN chmod +x /custom-services.d/safedesk-rdp-audio

# --- Audio SafeDesk : setup init (client.conf + default.pa propre + nettoyage verrous) ---
COPY files/custom-cont-init.d/safedesk-audio-setup /custom-cont-init.d/safedesk-audio-setup
RUN chmod +x /custom-cont-init.d/safedesk-audio-setup
