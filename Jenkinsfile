pipeline {
    agent any

    environment {
        DOCKERHUB_CREDENTIALS_ID = 'docker_cred'
        BRANCH_NAME = "${env.BRANCH_NAME}"
        IMAGE_TAG   = "${BRANCH_NAME}-${BUILD_NUMBER}"
    }

    stages {

        stage('Checkout Source') {
            steps {
                checkout scm
            }
        }

        stage('Verify Branch') {
            steps {
                script {
                    if (env.BRANCH_NAME != "feature/Maqsood-khan") {
                        error("❌ This pipeline only runs for feature/Maqsood-khan branch")
                    }
                }
            }
        }

        stage('Docker Hub Login') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: "${DOCKERHUB_CREDENTIALS_ID}",
                    usernameVariable: 'DOCKERHUB_USER',
                    passwordVariable: 'DOCKERHUB_PASS'
                )]) {
                    sh '''
                        echo $DOCKERHUB_PASS | docker login -u $DOCKERHUB_USER --password-stdin
                    '''
                }
            }
        }

        stage('Build & Tag Images') {
            steps {
                script {
                    env.FRONTEND_TAG_DH = "${DOCKERHUB_USER}/three-tier-app-frontend:${IMAGE_TAG}"
                    env.BACKEND_TAG_DH  = "${DOCKERHUB_USER}/three-tier-app-backend:${IMAGE_TAG}"

                    sh """
                        docker build -t ${BACKEND_TAG_DH} ./backend
                        docker build -t ${FRONTEND_TAG_DH} ./frontend
                    """
                }
            }
        }

        stage('Push Images to Docker Hub') {
            steps {
                sh """
                    docker push ${BACKEND_TAG_DH}
                    docker push ${FRONTEND_TAG_DH}
                """
            }
        }

        stage('Prepare .env for Compose') {
            steps {
                script {
                    writeFile file: '.env', text: """
BACKEND_IMAGE=${BACKEND_TAG_DH}
FRONTEND_IMAGE=${FRONTEND_TAG_DH}
"""
                }
            }
        }

        stage('Deploy Environment') {
            steps {
                sh """
                    docker-compose --env-file .env down
                    docker-compose --env-file .env pull
                    docker-compose --env-file .env up -d --remove-orphans
                """
            }
        }

        stage('Cleanup Local Images') {
            steps {
                sh """
                    docker rmi ${BACKEND_TAG_DH} ${FRONTEND_TAG_DH} || true
                """
            }
        }
    }

    post {
        success {
            echo "✅ feature/Maqsood-khan deployed successfully using Docker Hub images!"
        }
        failure {
            echo "❌ Pipeline failed for feature/Maqsood-khan. Check logs."
        }
    }
}
