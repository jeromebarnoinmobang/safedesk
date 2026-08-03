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

# Lanceur maison : fait heriter Chrome du profil de rendu detecte (/etc/chromium.d/zz-render)
COPY files/usr/local/bin/wrapped-google-chrome /usr/local/bin/wrapped-google-chrome
RUN set -eux; \
    chmod +x /usr/local/bin/wrapped-google-chrome; \
    if [ -f /usr/share/applications/google-chrome.desktop ]; then \
      sed -i 's|^Exec=/usr/bin/google-chrome-stable|Exec=/usr/local/bin/wrapped-google-chrome|' \
        /usr/share/applications/google-chrome.desktop; \
    fi