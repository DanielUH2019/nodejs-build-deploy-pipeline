// =============================================================================
// Jenkinsfile — build, unit-test and deploy a Node.js (Express) service to
// THREE targets, mirroring the three branches of the course repo:
//
//   Target (SSH/systemd)  <- first-deployment-pipeline
//   Docker                <- challenge_3
//   Kubernetes            <- deploy-to-kubernetes
//
// Flow:
//   Checkout -> Unit Test -> Deploy to Target (SSH)
//            -> Docker Build & Push -> Deploy to Docker -> Deploy to Kubernetes
//
// Node.js is provisioned by the NodeJS plugin (pinned to Node 24) so every
// agent tests/builds with the same interpreter.
// =============================================================================
pipeline {
    agent any

    options {
        disableConcurrentBuilds()                      // never deploy two builds at once
        timeout(time: 15, unit: 'MINUTES')             // abort if something hangs
        buildDiscarder(logRotator(numToKeepStr: '20')) // keep only the last 20 builds
    }

    // Provision Node.js 24 on PATH for every stage.
    // PREREQUISITE: under Manage Jenkins -> Tools -> NodeJS installations,
    // add an installation named exactly 'node-24' (requires the "NodeJS" plugin).
    tools {
        nodejs 'node-24'
    }

    // Only the SSH/target deploy needs parameters. Leave TARGET_HOST empty to
    // skip that stage and still run the Docker + Kubernetes deploys.
    parameters {
        string(
            name: 'TARGET_HOST',
            defaultValue: '',
            description: 'SSH target host DNS name / IP for the systemd deploy (empty = skip the target deploy)'
        )
        string(
            name: 'SSH_CREDENTIALS_ID',
            defaultValue: 'target-ssh-key',
            description: 'Jenkins "SSH Username with private key" credential ID'
        )
    }

    environment {
        APP_PORT      = '4444'                       // port the service listens on (see index.js)

        // --- Docker / Kubernetes image (ephemeral ttl.sh registry, no creds) ---
        IMAGE         = 'ttl.sh/danieluh2019-node:2h'

        // --- Docker target ---
        CONTAINER     = 'myapp'

        // --- Kubernetes target ---
        POD           = 'myapp'
        KUBE_SERVER   = 'https://kubernetes:6443'     // cluster API server reachable from the agent
        KUBE_CRED     = 'jenkins-robot-token'         // "Secret text" cred: default:jenkins-robot SA token

        // --- SSH / systemd target ---
        REMOTE_APP_DIR = '/opt/myapp'                 // install dir on the target
        SERVICE_NAME   = 'myapp'                      // systemd service name
        SERVICE_USER   = 'myapp'                      // unprivileged user the service runs as
        SSH_OPTIONS    = '-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=.ssh/known_hosts'
        HEALTH_CHECK_RETRIES       = '30'
        HEALTH_CHECK_SLEEP_SECONDS = '2'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        // --- Run the node:test unit suite -----------------------------------
        stage('Unit Test') {
            steps {
                sh 'node --version'
                sh 'npm install'
                sh 'npm test'
            }
        }

        // ===== Target 1: SSH / systemd (first-deployment-pipeline) ==========
        // The heavy lifting lives in versioned, shellcheck-able scripts/.
        stage('Deploy to Target (SSH)') {
            when { expression { return params.TARGET_HOST?.trim() } }
            steps {
                script { env.TARGET_HOST = params.TARGET_HOST.trim() }
                withCredentials([
                    sshUserPrivateKey(
                        credentialsId: params.SSH_CREDENTIALS_ID,
                        keyFileVariable: 'SSH_KEY',
                        usernameVariable: 'SSH_USER'
                    )
                ]) {
                    sh 'bash scripts/deploy.sh'
                }
                sh 'bash scripts/health-check.sh'
            }
        }

        // ===== Build the image once, reused by Docker + Kubernetes ==========
        stage('Docker Build and Push') {
            steps {
                sh 'docker buildx build --platform linux/amd64 -t ${IMAGE} --push .'
            }
        }

        // ===== Target 2: Docker (challenge_3) ===============================
        stage('Deploy to Docker') {
            steps {
                sh 'docker rm -f ${CONTAINER} || true'
                sh 'docker pull ${IMAGE}'
                sh 'docker run -d --name ${CONTAINER} --restart unless-stopped -p ${APP_PORT}:${APP_PORT} ${IMAGE}'
                sh '''#!/usr/bin/env bash
                    set -euo pipefail
                    echo "Waiting for container to become healthy..."
                    for i in $(seq 1 15); do
                        STATUS="$(docker inspect --format='{{.State.Health.Status}}' ${CONTAINER} 2>/dev/null || true)"
                        echo "  attempt $i: ${STATUS:-unknown}"
                        if [ "$STATUS" = "healthy" ]; then
                            echo "Container is healthy"
                            exit 0
                        fi
                        sleep 2
                    done
                    echo "Container failed to become healthy within 30s" >&2
                    docker logs ${CONTAINER} || true
                    exit 1
                '''
            }
        }

        // ===== Target 3: Kubernetes (deploy-to-kubernetes) ==================
        stage('Deploy to Kubernetes') {
            steps {
                withKubeConfig(serverUrl: env.KUBE_SERVER, credentialsId: env.KUBE_CRED) {
                    sh 'kubectl auth can-i create pods -n default'
                    // The :2h tag is reused every build, so apply alone would be a
                    // no-op against an unchanged spec and never pull the new image.
                    // Recreate the Pod so imagePullPolicy: Always fetches the push.
                    sh 'kubectl delete pod ${POD} --ignore-not-found --wait'
                    sh 'kubectl apply -f pod.yaml'
                    sh 'kubectl apply -f service.yaml'
                    sh 'kubectl wait --for=condition=Ready pod/${POD} --timeout=90s'
                    sh 'kubectl get pod ${POD} -o wide'
                    sh 'kubectl get service ${POD} -o wide'
                }
            }
        }
    }

    post {
        success {
            echo "All requested deploys of ${env.SERVICE_NAME} succeeded."
        }
        failure {
            echo "Pipeline FAILED. Check the stage logs above."
        }
        always {
            sh 'docker image prune -f || true'  // drop dangling build layers
            deleteDir()                         // wipe workspace (secrets/known_hosts/artifacts)
        }
    }
}
