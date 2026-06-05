# PROMPTS.md — agent-session documentation

How this repo was built with an AI coding agent (Claude Code), for the
Harbour.Space CS411 DevOps final exam. The task: a Jenkins build/test/deploy
pipeline for a small Node.js (Express) service, deploying to **three** targets —
target (SSH/systemd), Docker, and Kubernetes (`https://kubernetes:6443`).

## Transfer story: reused Go prompts, or re-derived for Node.js?

**Re-derived for Node.js — I reused the *shape*, not the *prompts*.**

The course reference repo (`DanielUH2019/harbour-space-cs411-devops`) already
solves the same exam for a **Go** app across three branches:

| Reference branch | Deploy style |
|------------------|--------------|
| `first-deployment-pipeline` | SSH + `systemd` |
| `challenge_3` | Docker |
| `deploy-to-kubernetes` | Kubernetes via `withKubeConfig` |

I did **not** copy the Go prompts. Instead I pointed the agent at those branches
as *structural references* and asked it to re-derive the Node.js equivalent. What
transferred was architecture; what was re-derived was every language-specific
detail:

- **Transferred (shape):** one declarative `Jenkinsfile`; ttl.sh ephemeral
  registry (no creds); `withKubeConfig` + a ServiceAccount bearer token;
  Pod+Service manifests with `imagePullPolicy: Always` and a delete-before-apply
  to force a re-pull of the reused `:2h` tag; an SSH deploy that stages files and
  runs a privileged installer on the target.
- **Re-derived (Node specifics):** `npm install` / `node --test` instead of
  `go build`/`go test`; a `node:24-alpine` Dockerfile installing only `express`;
  a systemd unit running `node /opt/myapp/index.js` (not a compiled Go binary);
  the target installer became "copy sources + `npm install --omit=dev`" instead
  of "ship one static binary."

The Go→Node gap that mattered most: the Go reference ships a **single static
binary**, so its SSH deploy just `scp`s one file. Node has no such artifact, so
the re-derived target deploy had to copy `index.js` + `package*.json` and run
`npm install --omit=dev` *on the target*, then render the systemd unit with the
target's actual `node` path. Reusing the Go prompt verbatim here would have been
wrong.

## One specific prompt

The opening instruction that set the whole task (lightly condensed):

> "Create a new public repo in my account for the final exam. Check mainly the
> `first-deployment-pipeline` branch and the one related to kubernetes. It uses
> NodeJS 24 (not a hard requirement). Uses the following `index.js` … and the
> following `index.test.js` … verbatim. Executes a unit test stage. Is deployed
> to target, docker, kubernetes. The Kubernetes endpoint: `https://kubernetes:6443`.
> Use whatever node version is available. The solution needs to be as simple as
> possible."

A follow-up sharpened the scope:

> "We need to deploy our app in 3 places, target (through ssh), docker and
> kubernetes — they are 3 different terminals. Also check the branch that does
> the deploy to docker. The Jenkinsfile needs to properly set up node."

Concrete constraints the agent had to honour from these prompts: **verbatim**
`index.js`/`index.test.js` (no edits allowed), **all three** deploy targets in
one pipeline, the fixed k8s endpoint, and "as simple as possible" (which is why
the NodeJS plugin / `tools` block was later dropped in favour of the Node already
on the agent's PATH).

## One friction moment

**`npm test` failed with `EADDRINUSE: address already in use :::4444`.**

This was subtle because the exam code is untouchable. `index.test.js` does
`require('./index')`, and `index.js` calls `app.listen(4444)` *at import time* —
so simply running the unit test **binds port 4444 on the Jenkins agent**. On its
own that's fine. The conflict came from the Docker deploy stage, which runs the
container with `--restart unless-stopped -p 4444:4444`; that container survives
across builds, so the *next* build's Unit Test stage tried to bind 4444 while the
previous build's container still held it → crash.

Because `index.js`/`index.test.js` had to stay verbatim, the fix had to live
entirely in the pipeline: before testing, free port 4444 on the agent (remove the
old `myapp` container, remove any container publishing 4444, and `fuser -k
4444/tcp` for a stray process), all best-effort so it's a no-op on a clean agent.
The Docker deploy stage was hardened the same way so `docker run -p` can't fail
with "port is already allocated."

A second friction moment, on the SSH/target deploy, was a stubborn
`Permission denied (publickey)`. The auth log showed sshd *accepting a different
key* and rejecting ours even though `grep -F` found our key's text in
`authorized_keys`. Root cause: the public key had been appended **without a
leading newline**, gluing it onto the end of the previous key's comment field —
present as a substring, but not a parseable key entry. Fix: append a newline
first, then the key (`printf '\n' | sudo tee -a authorized_keys`), re-fix
perms — loopback `ssh` then succeeded.

## One verification step

The SSH/target deploy is verified by an **agent-side health check** that polls the
live service until it returns the expected JSON ([`scripts/health-check.sh`](scripts/health-check.sh)):

```bash
curl -fsS "http://$TARGET_HOST:4444/" \
  | grep -q '"name":"Hello"' \
  && curl -fsS "http://$TARGET_HOST:4444/" | grep -q '"description":"World"'
```

It retries (30 × 2s) because a freshly restarted `systemd` service needs a moment
to bind. Note the **lowercase** JSON keys — `res.json(Sample(...))` emits
`{"name":"Hello","description":"World",...}`, so the grep had to match lowercase,
which I confirmed against the verbatim `index.js` rather than assuming.

Other verification gates in the pipeline:

- **Unit test:** `node --test` must pass (`Sample("localhost").url === "localhost"`).
- **Docker:** wait for the container `HEALTHCHECK` to report `healthy`
  (`docker inspect --format '{{.State.Health.Status}}'`, 15 × 2s).
- **Kubernetes:** `kubectl auth can-i create pods` → then
  `kubectl wait --for=condition=Ready pod/myapp --timeout=90s`.
