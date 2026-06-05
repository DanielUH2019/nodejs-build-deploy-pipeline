// =============================================================================
// Jenkinsfile — build, unit-test, containerise and deploy a Node.js service.
//
// Declarative pipeline. Flow:
//   Checkout -> Unit Test -> Docker Build & Push -> Deploy to Kubernetes
//
// "docker"     target: the image is pushed to the ephemeral ttl.sh registry.
// "kubernetes" target: a Pod + Service are applied to https://kubernetes:6443.
//
// No `tools` block: the build uses whatever Node.js is already on the agent's
// PATH (per the exam — Node 24 is not a hard requirement).
// =============================================================================
pipeline {
    agent any

    options {
        disableConcurrentBuilds()                      // never deploy two builds at once
        timeout(time: 10, unit: 'MINUTES')             // abort if something hangs
        buildDiscarder(logRotator(numToKeepStr: '20')) // keep only the last 20 builds
    }

    environment {
        IMAGE       = 'ttl.sh/danieluh2019-node:2h'   // ephemeral registry, no creds, expires in 2h
        POD         = 'myapp'
        KUBE_SERVER = 'https://kubernetes:6443'        // cluster API server reachable from the agent
        KUBE_CRED   = 'jenkins-robot-token'            // "Secret text" cred: default:jenkins-robot SA token
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        // Install dependencies and run the node:test unit suite.
        stage('Unit Test') {
            steps {
                sh 'npm install'
                sh 'npm test'
            }
        }

        // Build a linux/amd64 image and push it to ttl.sh in one step.
        stage('Docker Build and Push') {
            steps {
                sh 'docker buildx build --platform linux/amd64 -t ${IMAGE} --push .'
            }
        }

        // Apply the Pod + Service against the cluster. The Kubernetes CLI plugin
        // writes a temporary kubeconfig wired to KUBE_SERVER and authenticated
        // with the jenkins-robot bearer token (insecure-skip-tls-verify, since no
        // CA cert is supplied).
        stage('Deploy to Kubernetes') {
            steps {
                withKubeConfig(serverUrl: env.KUBE_SERVER, credentialsId: env.KUBE_CRED) {
                    // Fail fast with a clear message if the token is missing/expired.
                    sh 'kubectl auth can-i create pods -n default'
                    // The :2h tag is reused every build, so `apply` alone would be a
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
            echo "Deploy of ${env.POD} to ${env.KUBE_SERVER} succeeded."
        }
        failure {
            echo "Pipeline FAILED for ${env.POD}. Check the stage logs above."
        }
        always {
            deleteDir()  // wipe the workspace so artifacts/creds do not linger
        }
    }
}
