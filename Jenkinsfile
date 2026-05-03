pipeline {
    agent any

    environment {
        DOCKERHUB_CREDENTIALS_ID = 'docker_cred'
        GITHUB_CREDENTIALS_ID    = 'git_cred'
        BRANCH_NAME = "${env.BRANCH_NAME}"
        IMAGE_TAG   = "${env.BRANCH_NAME}-${env.BUILD_NUMBER}"
    }

    stages {

        stage('Clone Repo') {
            steps {
                git branch: 'feature/Maqsood-khan',
                    url: 'https://github.com/Mr-Maqsood-Bangash/Food-Delivery.git',
                    credentialsId: "${GITHUB_CREDENTIALS_ID}"
            }
        }

        stage('Docker Hub Login') {
            steps {
                script {
                    withCredentials([usernamePassword(
                        credentialsId: "${DOCKERHUB_CREDENTIALS_ID}",
                        usernameVariable: 'DOCKERHUB_USER',
                        passwordVariable: 'DOCKERHUB_PASS'
                    )]) {
                        env.DOCKER_USER = DOCKERHUB_USER

                        sh '''
                            echo $DOCKERHUB_PASS | docker login -u $DOCKERHUB_USER --password-stdin
                        '''
                    }
                }
            }
        }

        stage('Build & Tag Images') {
            steps {
                script {
                    env.FRONTEND_TAG_DH = "${env.DOCKER_USER}/three-tier-app-frontend:${env.IMAGE_TAG}"
                    env.BACKEND_TAG_DH  = "${env.DOCKER_USER}/three-tier-app-backend:${env.IMAGE_TAG}"

                    sh """
                        docker build -t ${env.BACKEND_TAG_DH} ./backend
                        docker build -t ${env.FRONTEND_TAG_DH} ./frontend
                    """
                }
            }
        }

        stage('Push Images to Docker Hub') {
            steps {
                sh """
                    docker push ${env.BACKEND_TAG_DH}
                    docker push ${env.FRONTEND_TAG_DH}
                """
            }
        }

        stage('Prepare .env for Compose') {
            steps {
                script {
                    writeFile file: '.env', text: """BACKEND_IMAGE=${env.BACKEND_TAG_DH}
FRONTEND_IMAGE=${env.FRONTEND_TAG_DH}
"""
                }
            }
        }

        stage('Deploy Environment') {
            steps {
                dir("${WORKSPACE}") {
                    sh """
                        docker compose --env-file .env down
                        docker compose --env-file .env pull
                        docker compose --env-file .env up -d --remove-orphans
                    """
                }
            }
        }

        stage('Cleanup Local Images') {
            steps {
                sh """
                    docker rmi ${env.BACKEND_TAG_DH} ${env.FRONTEND_TAG_DH} || true
                """
            }
        }
    }

    post {
        success {
            echo "✅ ${env.BRANCH_NAME} environment deployed successfully using Docker Hub images!"
        }

        failure {
            echo "❌ Deployment failed for ${env.BRANCH_NAME}. Check logs."
        }
    }
}
