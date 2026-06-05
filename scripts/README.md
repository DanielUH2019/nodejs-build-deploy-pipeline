# SSH / systemd deploy scripts

These scripts back the **Deploy to Target (SSH)** stage of [`../Jenkinsfile`](../Jenkinsfile).
The Jenkinsfile only *orchestrates* — the real deploy logic lives here so it can
be read, linted with `shellcheck`, and run by hand when debugging.

## Files

| File | Runs on | Purpose |
|------|---------|---------|
| `deploy.sh` | Jenkins agent | Pre-trust the host key, copy app sources + unit template to the target over SSH, invoke `remote-install.sh` there. |
| `remote-install.sh` | Target host | Privileged install: create the service user, copy sources, `npm install --omit=dev`, render + install the systemd unit, restart the service. |
| `myapp.service` | — | systemd unit **template** with `@@PLACEHOLDERS@@`; rendered by `remote-install.sh`. |
| `health-check.sh` | Jenkins agent | Poll `http://TARGET:4444/` until it returns the expected JSON. |

## How a deploy flows

```
Jenkins agent                                   Target host
-------------                                   -----------
deploy.sh
  ssh-keyscan -> .ssh/known_hosts
  scp index.js, package*.json, unit  ─────────▶  /tmp/myapp-stage.XXXX/
  ssh ... sh -s < remote-install.sh  ─────────▶  remote-install.sh
                                                   useradd (if needed)
                                                   copy sources -> /opt/myapp
                                                   npm install --omit=dev
                                                   render+install unit -> /etc/systemd/system/myapp.service
                                                   systemctl daemon-reload / enable / restart
health-check.sh
  curl http://TARGET:4444/  (retry loop)
```

## Requirements on the target

- **Node.js + npm** already installed and on PATH (the unit runs `node index.js`).
- **systemd**, and the SSH user has **passwordless sudo** for the `install`,
  `useradd`, `npm`, `tee`, `chown` and `systemctl` commands in `remote-install.sh`.

## Running by hand (debugging)

```bash
export TARGET_HOST=1.2.3.4
export SSH_KEY=~/.ssh/id_ed25519 SSH_USER=deploy
export SSH_OPTIONS='-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=.ssh/known_hosts'
export REMOTE_APP_DIR=/opt/myapp SERVICE_NAME=myapp SERVICE_USER=myapp
bash scripts/deploy.sh
```
