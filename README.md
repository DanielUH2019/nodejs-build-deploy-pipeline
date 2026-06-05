# nodejs-build-deploy-pipeline

Build and deployment pipeline for a small Node.js (Express) service — the final
exam for the Harbour.Space **CS411 DevOps** course.

A Jenkins declarative pipeline runs a unit-test stage, builds a Docker image, and
deploys the app to both the **docker** and **kubernetes** targets.

## The app

`index.js` is a one-endpoint Express service listening on port **4444**:

```bash
curl localhost:4444
# {"name":"Hello","description":"World","url":"localhost:4444"}
```

`index.test.js` is the unit test, using the built-in `node:test` runner.

## Pipeline (`Jenkinsfile`)

| Stage | What it does |
|-------|--------------|
| **Checkout** | Fetch the source. |
| **Unit Test** | `npm install` then `npm test` (`node --test`). |
| **Docker Build and Push** | `docker buildx build --platform linux/amd64 -t ttl.sh/danieluh2019-node:2h --push .` — the **docker** target (ephemeral [ttl.sh](https://ttl.sh) registry, no credentials). |
| **Deploy to Kubernetes** | `kubectl apply -f pod.yaml -f service.yaml` against `https://kubernetes:6443` via the Kubernetes CLI plugin — the **kubernetes** target. |

The pipeline uses whatever Node.js is on the agent's PATH (no version pinning);
Node 24 is not a hard requirement.

## Jenkins prerequisites

The agent must have on its PATH: **Node.js + npm**, **Docker** (with `buildx`),
and **kubectl**. The controller needs:

- The **Kubernetes CLI** plugin (provides `withKubeConfig`).
- A **Secret text** credential with ID `jenkins-robot-token` holding the bearer
  token of the `default:jenkins-robot` ServiceAccount, with permission to manage
  Pods/Services in the `default` namespace.

## Run locally (without Jenkins)

```bash
npm install
npm test                                   # unit test

docker build -t myapp:test .
docker run --rm -p 4444:4444 myapp:test    # then: curl localhost:4444

kubectl apply --dry-run=client -f pod.yaml -f service.yaml   # validate manifests
```
