# nodejs-build-deploy-pipeline

Build and deployment pipeline for a small Node.js (Express) service — the final
exam for the Harbour.Space **CS411 DevOps** course.

A single Jenkins declarative pipeline runs a unit-test stage and then deploys the
app to **three targets**:

| Target | How | Reference branch |
|--------|-----|------------------|
| **target** (SSH) | Copy sources over SSH, run as a `systemd` service | `first-deployment-pipeline` |
| **docker** | Build + push to ttl.sh, then `docker run` | `challenge_3` |
| **kubernetes** | `kubectl apply` against `https://kubernetes:6443` | `deploy-to-kubernetes` |

## The app

`index.js` is a one-endpoint Express service on port **4444**:

```bash
curl localhost:4444
# {"name":"Hello","description":"World","url":"localhost:4444"}
```

`index.test.js` is the unit test (built-in `node:test` runner).

## Pipeline (`Jenkinsfile`)

| Stage | What it does |
|-------|--------------|
| **Checkout** | Fetch the source. |
| **Unit Test** | `npm install` then `npm test` (`node --test`). |
| **Deploy to Target (SSH)** | `scripts/deploy.sh` → systemd service on `TARGET_HOST`, then `scripts/health-check.sh`. Skipped if `TARGET_HOST` is empty. |
| **Docker Build and Push** | `docker buildx build ... -t ttl.sh/danieluh2019-node:2h --push .` |
| **Deploy to Docker** | `docker run -p 4444:4444 ...`, then wait for the container `HEALTHCHECK` to report healthy. |
| **Deploy to Kubernetes** | `kubectl apply -f pod.yaml -f service.yaml` via the Kubernetes CLI plugin. |

## Build parameters

Only the SSH/target deploy is parameterised — Docker and Kubernetes need none:

| Parameter | Default | Meaning |
|-----------|---------|---------|
| `TARGET_HOST` | *(empty)* | SSH host for the systemd deploy. **Leave empty to skip** that stage and run only Docker + Kubernetes. |
| `SSH_CREDENTIALS_ID` | `target-ssh-key` | Jenkins "SSH Username with private key" credential ID. |

## Jenkins prerequisites

On the agent's PATH: **Node.js + npm** (used by the Unit Test stage — no version
pinned), **Docker** (with `buildx`), **kubectl**, **ssh/scp/ssh-keyscan/curl**.
On the controller:

- **Kubernetes CLI plugin** (provides `withKubeConfig`).
- **Secret text** credential `jenkins-robot-token` — bearer token of the
  `default:jenkins-robot` ServiceAccount (manage Pods/Services in `default`).
- For the SSH deploy: an **SSH Username with private key** credential
  (default ID `target-ssh-key`); the target needs Node.js + passwordless sudo
  (see [`scripts/README.md`](scripts/README.md)).

## Run locally (without Jenkins)

```bash
npm install
npm test                                   # unit test

docker build -t myapp:test .
docker run --rm -p 4444:4444 myapp:test    # then: curl localhost:4444

kubectl apply --dry-run=client -f pod.yaml -f service.yaml   # validate manifests
```
