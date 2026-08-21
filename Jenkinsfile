pipeline {
    agent any
    environment {
        DOCKERHUB_CREDENTIALS = credentials('dockerhub-creds')
        BACKEND_IMAGE  = "maqsoodbangash/food-backend"
        FRONTEND_IMAGE = "maqsoodbangash/food-frontend"
    }
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Check Skip Condition') {
            steps {
                script {
                    def lastCommitMsg = sh(
                        script: "git log -1 --pretty=%B",
                        returnStdout: true
                    ).trim()
                    echo "Last commit message: ${lastCommitMsg}"

                    if (lastCommitMsg.contains("automatic update") || lastCommitMsg.contains("ArgoCD Image Updater") || lastCommitMsg.contains("[skip ci]")) {
                        echo "Skipping build — this commit was made by ArgoCD Image Updater (avoiding CI/CD loop)."
                        currentBuild.result = 'ABORTED'
                        error("Stopping pipeline to prevent infinite loop.")
                    }
                }
            }
        }

        stage('Determine Versions') {
            steps {
                script {
                    // ---- Backend version ----
                    def backendResp = sh(
                        script: """
                            curl -s "https://hub.docker.com/v2/repositories/${BACKEND_IMAGE}/tags?page_size=100" | \
                            grep -o '"name":"v[0-9]*\\.[0-9]*\\.[0-9]*"' | \
                            sed 's/"name":"//;s/"//' | \
                            sort -V | tail -1
                        """,
                        returnStdout: true
                    ).trim()
                    if (backendResp == "") {
                        env.BACKEND_VERSION = "v1.0.0"
                    } else {
                        def p = backendResp.replace("v", "").split("\\.")
                        env.BACKEND_VERSION = "v${p[0]}.${p[1]}.${p[2].toInteger() + 1}"
                    }
                    echo "New backend version: ${env.BACKEND_VERSION}"
                    // ---- Frontend version ----
                    def frontendResp = sh(
                        script: """
                            curl -s "https://hub.docker.com/v2/repositories/${FRONTEND_IMAGE}/tags?page_size=100" | \
                            grep -o '"name":"v[0-9]*\\.[0-9]*\\.[0-9]*"' | \
                            sed 's/"name":"//;s/"//' | \
                            sort -V | tail -1
                        """,
                        returnStdout: true
                    ).trim()
                    if (frontendResp == "") {
                        env.FRONTEND_VERSION = "v1.0.0"
                    } else {
                        def p = frontendResp.replace("v", "").split("\\.")
                        env.FRONTEND_VERSION = "v${p[0]}.${p[1]}.${p[2].toInteger() + 1}"
                    }
                    echo "New frontend version: ${env.FRONTEND_VERSION}"
                }
            }
        }
        stage('Build Images') {
            parallel {
                stage('Build Backend') {
                    steps {
                        dir('backend') {
                            sh 'docker build -t $BACKEND_IMAGE:$BACKEND_VERSION .'
                        }
                    }
                }
                stage('Build Frontend') {
                    steps {
                        dir('frontend') {
                            sh 'docker build -t $FRONTEND_IMAGE:$FRONTEND_VERSION .'
                        }
                    }
                }
            }
        }
        stage('Login to Docker Hub') {
            steps {
                sh 'echo $DOCKERHUB_CREDENTIALS_PSW | docker login -u $DOCKERHUB_CREDENTIALS_USR --password-stdin'
            }
        }
        stage('Push Images') {
            parallel {
                stage('Push Backend') {
                    steps {
                        sh 'docker push $BACKEND_IMAGE:$BACKEND_VERSION'
                    }
                }
                stage('Push Frontend') {
                    steps {
                        sh 'docker push $FRONTEND_IMAGE:$FRONTEND_VERSION'
                    }
                }
            }
        }
    }
    post {
        success {
            echo "✅ Backend pushed: ${BACKEND_IMAGE}:${BACKEND_VERSION}"
            echo "✅ Frontend pushed: ${FRONTEND_IMAGE}:${FRONTEND_VERSION}"
        }
        failure {
            echo "❌ Pipeline failed"
        }
        aborted {
            echo "⏭️ Build skipped to prevent CI/CD loop."
        }
        always {
            sh 'docker logout || true'
        }
    }
}
