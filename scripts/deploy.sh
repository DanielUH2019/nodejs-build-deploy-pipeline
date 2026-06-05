#!/usr/bin/env bash
#
# deploy.sh — ship the Node.js app to the target host and (re)start it.
#
# Runs ON THE JENKINS AGENT. It uploads the app sources (index.js, package.json,
# package-lock.json) and the systemd unit template to a staging dir on the
# target over SSH, then runs `remote-install.sh` ON THE TARGET to do the
# privileged install (npm install --omit=dev + systemd unit + restart).
#
# Inputs (all exported by the Jenkins pipeline):
#   TARGET_HOST     - DNS name / IP of the machine to deploy to   (param)
#   SSH_KEY         - path to the private key file   (from withCredentials)
#   SSH_USER        - SSH username                    (from withCredentials)
#   SSH_OPTIONS     - common ssh/scp flags (BatchMode, known_hosts, ...)
#   REMOTE_APP_DIR  - install directory on the target (e.g. /opt/myapp)
#   SERVICE_NAME    - systemd service name (e.g. myapp)
#   SERVICE_USER    - unprivileged user the service runs as
set -euo pipefail

: "${TARGET_HOST:?TARGET_HOST must be set}"
: "${SSH_KEY:?SSH_KEY must be set (provided by withCredentials)}"
: "${SSH_USER:?SSH_USER must be set (provided by withCredentials)}"
: "${SSH_OPTIONS:?SSH_OPTIONS must be set}"
: "${REMOTE_APP_DIR:?REMOTE_APP_DIR must be set}"
: "${SERVICE_NAME:?SERVICE_NAME must be set}"
: "${SERVICE_USER:?SERVICE_USER must be set}"

# Locate this script's dir and the repo root (where index.js lives).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT_TEMPLATE="$SCRIPT_DIR/myapp.service"
REMOTE_INSTALL="$SCRIPT_DIR/remote-install.sh"

ssh_target="$SSH_USER@$TARGET_HOST"

# --- Lock down the local SSH material --------------------------------------
# SSH refuses to use a private key with loose permissions. known_hosts is
# workspace-relative to match UserKnownHostsFile in SSH_OPTIONS.
chmod 600 "$SSH_KEY"
mkdir -p .ssh
touch .ssh/known_hosts
chmod 700 .ssh
chmod 600 .ssh/known_hosts

echo "Pre-trusting SSH host key for $TARGET_HOST ..."
if ! known_hosts_entry="$(ssh-keyscan -T 10 -H "$TARGET_HOST" 2>/dev/null)" \
    || [ -z "$known_hosts_entry" ]; then
    echo "Could not fetch SSH host key for $TARGET_HOST" >&2
    exit 1
fi
printf '%s\n' "$known_hosts_entry" >> .ssh/known_hosts

# --- Create a staging dir on the target ------------------------------------
# shellcheck disable=SC2086  # SSH_OPTIONS must word-split
remote_stage="$(ssh $SSH_OPTIONS -i "$SSH_KEY" "$ssh_target" 'mktemp -d /tmp/myapp-stage.XXXXXX')"

cleanup() {
    # shellcheck disable=SC2086
    ssh $SSH_OPTIONS -i "$SSH_KEY" "$ssh_target" "rm -rf '$remote_stage'" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# --- Upload app sources + unit template ------------------------------------
# shellcheck disable=SC2086
scp $SSH_OPTIONS -i "$SSH_KEY" \
    "$APP_DIR/index.js" \
    "$APP_DIR/package.json" \
    "$APP_DIR/package-lock.json" \
    "$UNIT_TEMPLATE" \
    "$ssh_target:$remote_stage/"

# --- Run the privileged installer on the target ----------------------------
echo "Installing $SERVICE_NAME on $TARGET_HOST ..."
# shellcheck disable=SC2086
ssh $SSH_OPTIONS -i "$SSH_KEY" "$ssh_target" \
    "REMOTE_STAGE='$remote_stage' REMOTE_APP_DIR='$REMOTE_APP_DIR' SERVICE_NAME='$SERVICE_NAME' SERVICE_USER='$SERVICE_USER' sh -s" \
    < "$REMOTE_INSTALL"

echo "Deploy of $SERVICE_NAME to $TARGET_HOST completed."
