#!/usr/bin/env bash
# OPTIONAL SHORTCUT. The README (One-time setup, step 3) prepares the VM by hand with a
# normal `mathew` account. This script does the same Docker, group, key and folder steps
# in one go for tidewater-departures on port 8081, on the Azure VM (Ubuntu 24.04, x64).
#
# Create the account first so it has a password for sudo (as azureuser on the VM):
#   sudo adduser mathew
# Then, from this project folder on your laptop, once per public key:
#   scp deploy/vps-setup.sh azureuser@<vm-ip>:/tmp/
#   ssh -t azureuser@<vm-ip> "sudo bash /tmp/vps-setup.sh mathew '<one .pub line>'"
#
# If the user does not exist, the script creates it with no password (key-only, no sudo).
# Arguments: <linux-user> [<public-key>]
# It installs Docker if it is missing, creates the Linux user if it does not exist
# (no password, SSH key only), lets it run Docker, installs the public key for it,
# creates /opt/tidewater-departures owned by it, and opens the port in ufw if ufw is
# active. Azure's own firewall (the network security group) sits outside the VM, so
# port 8081 is opened there separately, in the portal. The script never receives a
# private key or any other secret. Safe to run again.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

DEPLOY_USER="${1:?usage: vps-setup.sh <linux-user> [<public-key>]}"
PUBKEY="${2:-}"
APP_NAME="${APP_NAME:-tidewater-departures}"
APP_PORT="${APP_PORT:-8081}"
APP_DIR="/opt/$APP_NAME"

if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "[setup] WARNING: this VM is $(uname -m). The pipeline builds x86_64 images,"
  echo "[setup] so deploys will fail. Recreate it with an x64 size (B2ats v2 or B1s)."
fi

if ! command -v curl >/dev/null 2>&1; then
  apt-get update -qq && apt-get install -y -qq curl
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "[setup] installing docker"
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker

if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
  echo "[setup] creating user $DEPLOY_USER"
  # "*" = no password login at all, but not "locked", which some sshd setups refuse.
  useradd -m -s /bin/bash -p "*" "$DEPLOY_USER"
fi
usermod -aG docker "$DEPLOY_USER"

if [[ -n "$PUBKEY" ]]; then
  home="$(getent passwd "$DEPLOY_USER" | cut -d: -f6)"
  install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$home/.ssh"
  touch "$home/.ssh/authorized_keys"
  grep -qxF "$PUBKEY" "$home/.ssh/authorized_keys" || echo "$PUBKEY" >> "$home/.ssh/authorized_keys"
  chown "$DEPLOY_USER":"$DEPLOY_USER" "$home/.ssh/authorized_keys"
  chmod 600 "$home/.ssh/authorized_keys"
  echo "[setup] public key installed for $DEPLOY_USER"
fi

mkdir -p "$APP_DIR/bin" "$APP_DIR/state"
chown -R "$DEPLOY_USER":"$DEPLOY_USER" "$APP_DIR"
echo "[setup] $APP_DIR ready, owned by $DEPLOY_USER"

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow "${APP_PORT}/tcp" >/dev/null && echo "[setup] ufw: opened port ${APP_PORT}"
fi

# Warn if another program holds the port. Our own container holding it is fine.
if ss -ltnH "sport = :${APP_PORT}" 2>/dev/null | grep -q . \
   && [[ -z "$(docker ps -q --filter "name=^${APP_NAME}\$")" ]]; then
  echo "[setup] WARNING: something else is already listening on port ${APP_PORT}:"
  ss -ltnpH "sport = :${APP_PORT}" || true
  echo "[setup] the first deploy will fail until that port is free."
fi

echo "[setup] done. Next:"
echo "  1. Azure portal: open inbound port ${APP_PORT} on this VM's network security group."
echo "  2. From your laptop: ssh -i ~/.ssh/${APP_NAME}-deploy ${DEPLOY_USER}@<vm-ip> docker ps"
