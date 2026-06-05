#!/bin/sh
#
# remote-install.sh — install and (re)start the Node.js service ON THE TARGET.
#
# `deploy.sh` streams this over SSH (`ssh ... sh -s < remote-install.sh`), so it
# runs on the target. Must be POSIX sh (no bash-isms) — the target may use
# dash/busybox as /bin/sh. Privileged steps use `sudo`; the SSH user therefore
# needs passwordless sudo for these commands.
#
# Assumes Node.js + npm are already installed and on PATH on the target.
#
# Inputs (exported by deploy.sh through the ssh command line):
#   REMOTE_STAGE    - staging dir holding the uploaded files in /tmp
#   REMOTE_APP_DIR  - install directory (e.g. /opt/myapp)
#   SERVICE_NAME    - systemd service name (e.g. myapp)
#   SERVICE_USER    - unprivileged system user to run the service as
set -eu

: "${REMOTE_STAGE:?}"
: "${REMOTE_APP_DIR:?}"
: "${SERVICE_NAME:?}"
: "${SERVICE_USER:?}"

# --- 0. Verify Node.js + npm are present -----------------------------------
NODE_BIN="$(command -v node || true)"
NPM_BIN="$(command -v npm || true)"
if [ -z "$NODE_BIN" ] || [ -z "$NPM_BIN" ]; then
    echo "node/npm not found on the target PATH; install Node.js first" >&2
    exit 1
fi
echo "Using node at $NODE_BIN ($("$NODE_BIN" --version))"

# --- 1. Ensure the install dir + unprivileged service user -----------------
sudo install -d -m 0755 -o root -g root "$REMOTE_APP_DIR"

if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
    nologin_shell=/usr/sbin/nologin
    [ -x "$nologin_shell" ] || nologin_shell=/bin/false
    sudo useradd --system --home-dir "$REMOTE_APP_DIR" --shell "$nologin_shell" "$SERVICE_USER"
fi
if [ "$(id -u "$SERVICE_USER")" -eq 0 ]; then
    echo "$SERVICE_USER must not resolve to uid 0" >&2
    exit 1
fi

# --- 2. Copy app sources into place ----------------------------------------
sudo install -m 0644 -o root -g root "$REMOTE_STAGE/index.js"     "$REMOTE_APP_DIR/index.js"
sudo install -m 0644 -o root -g root "$REMOTE_STAGE/package.json" "$REMOTE_APP_DIR/package.json"
if [ -f "$REMOTE_STAGE/package-lock.json" ]; then
    sudo install -m 0644 -o root -g root "$REMOTE_STAGE/package-lock.json" "$REMOTE_APP_DIR/package-lock.json"
fi

# --- 3. Install production dependencies on the target ----------------------
( cd "$REMOTE_APP_DIR" && sudo "$NPM_BIN" install --omit=dev --no-audit --no-fund )

# --- 4. Render + install the systemd unit ----------------------------------
sed \
    -e "s|@@SERVICE_USER@@|$SERVICE_USER|g" \
    -e "s|@@REMOTE_APP_DIR@@|$REMOTE_APP_DIR|g" \
    -e "s|@@NODE_BIN@@|$NODE_BIN|g" \
    "$REMOTE_STAGE/myapp.service" \
    | sudo tee "/etc/systemd/system/$SERVICE_NAME.service" >/dev/null

# --- 5. Hand the install dir to the service user ---------------------------
sudo chown -R "$SERVICE_USER":"$SERVICE_USER" "$REMOTE_APP_DIR"

# --- 6. Reload systemd and (re)start the service ---------------------------
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl restart "$SERVICE_NAME"

rm -rf "$REMOTE_STAGE"
echo "Installed and restarted $SERVICE_NAME"
