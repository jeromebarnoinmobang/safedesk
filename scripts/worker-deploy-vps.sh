#!/usr/bin/env bash
# Root-owned entrypoint invoked only by the SafeDesk GitHub Actions worker.
set -euo pipefail

cd /opt/mobang/safedesk
git -c safe.directory=/opt/mobang/safedesk fetch --quiet origin main
git -c safe.directory=/opt/mobang/safedesk merge --ff-only origin/main
install -D -m 0644 deploy/traefik/safedesk-vpc.yml /opt/mobang/traefik/dynamic/safedesk-vpc.yml
export INSTALL_CHROME=true INSTALL_SUNSHINE=true SUNSHINE_BIND_IP=192.168.255.1
docker compose \
  -f docker-compose.yml \
  -f docker-compose.remote.yml \
  -f docker-compose.av.yml \
  -f docker-compose.sync-vpc.yml \
  -f docker-compose.phone.yml \
  up -d --build
docker exec mobang-desktop sunshine --version
