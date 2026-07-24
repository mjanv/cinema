#!/usr/bin/env bash
# One-time provisioning for the cinema app on the existing droplet.
# Run as root on the server. Safe to re-run.
#
# Assumes premiere-ecoute is already deployed: Traefik, Let's Encrypt and the
# firewall are its setup's responsibility, not this one's.
set -euo pipefail

APP=cinema
APP_DIR="/opt/${APP}"
APP_USER="${APP}"

echo "==> Creating ${APP_USER} service account"
if ! id -u "${APP_USER}" >/dev/null 2>&1; then
  # System account, no login shell: it only ever runs the release.
  useradd --system --create-home --home-dir "/home/${APP_USER}" \
    --shell /usr/sbin/nologin "${APP_USER}"
else
  echo "    already exists, skipping"
fi

echo "==> Creating ${APP_DIR}"
mkdir -p "${APP_DIR}"
chown "${APP_USER}:${APP_USER}" "${APP_DIR}"

echo "==> Installing systemd unit"
install -m 0644 "$(dirname "$0")/systemd/${APP}.service" "/etc/systemd/system/${APP}.service"
systemctl daemon-reload
systemctl enable "${APP}"

echo "==> Installing Traefik routing"
# /opt/traefik/dynamic/ is shared between the apps on this droplet; each owns
# one file and deploys it independently. The directory provider itself is
# configured in premiere-ecoute's traefik.yml.
TRAEFIK_DIR=/opt/traefik/dynamic

if ! grep -q 'directory: /opt/traefik/dynamic' /opt/traefik/traefik.yml 2>/dev/null; then
  echo "    ERROR: Traefik is not using the directory provider yet."
  echo "    Deploy premiere-ecoute first — its traefik.yml configures it."
  exit 1
fi

mkdir -p "${TRAEFIK_DIR}"
install -m 0644 "$(dirname "$0")/traefik/cinema.yml" "${TRAEFIK_DIR}/cinema.yml"
chown -R traefik:traefik /opt/traefik 2>/dev/null || true
echo "    installed ${TRAEFIK_DIR}/cinema.yml (watched; no restart needed)"

cat <<'NEXT'

==> Remaining manual steps

1. DNS: point cinema.premiere-ecoute.fr at this droplet (A record).
   Let's Encrypt cannot issue the certificate until this resolves.

2. Verify premiere-ecoute still serves after the Traefik provider change:
     curl -fsS -o /dev/null https://premiere-ecoute.fr/health && echo OK
   If it broke, restore the backup this script made:
     cp /opt/traefik/traefik.yml.bak.* /opt/traefik/traefik.yml
     systemctl restart traefik

3. GitHub secrets on the cinema repo:
     CINEMA_SECRET_KEY_BASE   generate with: mix phx.gen.secret
     DO_SSH_PRIVATE_KEY       the same deploy key premiere-ecoute uses
   And one variable:
     DO_HOST                  the droplet IP or hostname

4. Push to main. The workflow builds, deploys and health-checks; a failed
   check rolls back automatically.

NEXT
