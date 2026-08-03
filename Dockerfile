# Bureau KDE + Google Chrome officiel.
# Chromium (build non-brande) ne peut PAS connecter un compte Google au navigateur :
# Google reserve le jeton OAuth de sync a Chrome officiel depuis le 15/03/2021.
# On ajoute donc Chrome a l image, de maniere reproductible.
FROM lscr.io/linuxserver/webtop:debian-kde@sha256:2c69b3325b177713ac388fd8c0b95589bc537e938c5ff6e7a5435887fc35d0f6

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl gnupg; \
    curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
      | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg; \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
      > /etc/apt/sources.list.d/google-chrome.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends google-chrome-stable; \
    rm -rf /var/lib/apt/lists/*


# Claude Desktop (beta Linux : Chat + Cowork + Code) — depot apt officiel Anthropic.
# La cle est verifiee par empreinte : le build ECHOUE si elle ne correspond pas.
RUN set -eux; \
    curl -fsSLo /usr/share/keyrings/claude-desktop-archive-keyring.asc \
      https://downloads.claude.ai/claude-desktop/key.asc; \
    gpg --show-keys --with-colons /usr/share/keyrings/claude-desktop-archive-keyring.asc \
      | grep -q '31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE'; \
    echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main" \
      > /etc/apt/sources.list.d/claude-desktop.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends claude-desktop; \
    rm -rf /var/lib/apt/lists/*
# Lanceur maison : reutilise le profil de rendu (/etc/chromium.d/zz-render)

# Outils de travail : Node (requis par les MCP lances en npx), GitHub CLI, VS Code, git.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends nodejs git;   # npm/npx viennent avec nodejs (NodeSource) \
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
COPY files/usr/local/bin/wrapped-google-chrome /usr/local/bin/wrapped-google-chrome
RUN chmod +x /usr/local/bin/wrapped-google-chrome \
 && sed -i 's|^Exec=/usr/bin/google-chrome-stable|Exec=/usr/local/bin/wrapped-google-chrome|' \
      /usr/share/applications/google-chrome.desktop