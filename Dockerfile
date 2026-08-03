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

# Lanceur maison : reutilise le profil de rendu (/etc/chromium.d/zz-render)
COPY files/usr/local/bin/wrapped-google-chrome /usr/local/bin/wrapped-google-chrome
RUN chmod +x /usr/local/bin/wrapped-google-chrome \
 && sed -i 's|^Exec=/usr/bin/google-chrome-stable|Exec=/usr/local/bin/wrapped-google-chrome|' \
      /usr/share/applications/google-chrome.desktop