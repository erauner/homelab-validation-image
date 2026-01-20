#!/usr/bin/env groovy
/**
 * Jenkinsfile for homelab-validation-image
 *
 * Builds and pushes the CI validation container image on every merge to main.
 * Uses semantic versioning based on git tags.
 *
 * Image: docker.nexus.erauner.dev/homelab/validation:<version>
 */

@Library('homelab') _

pipeline {
    agent {
        kubernetes {
            yaml homelab.podTemplate('kaniko')
        }
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 30, unit: 'MINUTES')  // Longer timeout for large image
        disableConcurrentBuilds()
    }

    environment {
        IMAGE_NAME = 'docker.nexus.erauner.dev/homelab/validation'
    }

    stages {
        stage('Build and Push Image') {
            steps {
                script {
                    // Get version info
                    env.VERSION = homelab.gitDescribe()
                    env.COMMIT = homelab.gitShortCommit()

                    echo "Building validation image version: ${env.VERSION} (commit: ${env.COMMIT})"

                    // Build and push using shared library
                    homelab.homelabBuild([
                        image: env.IMAGE_NAME,
                        version: env.VERSION,
                        commit: env.COMMIT,
                        dockerfile: 'Dockerfile',
                        context: '.'
                    ])
                }
            }
        }

        stage('Create Release Tag') {
            steps {
                container('alpine') {
                    withCredentials([usernamePassword(
                        credentialsId: 'github-app',
                        usernameVariable: 'GIT_USER',
                        passwordVariable: 'GIT_TOKEN'
                    )]) {
                        script {
                            sh 'apk add --no-cache git curl jq'

                            // Use shared library for release creation
                            def result = homelab.createPreRelease([
                                repo: 'erauner/homelab-validation-image',
                                imageName: env.IMAGE_NAME,
                                imageTag: env.VERSION
                            ])
                            env.NEW_VERSION = result.version
                        }
                    }
                }
            }
        }
    }

    post {
        success {
            echo """
            ✅ Build successful!

            Image: ${env.IMAGE_NAME}:${env.VERSION}
            Tag: ${env.NEW_VERSION ?: 'N/A'}

            To pull: docker pull ${env.IMAGE_NAME}:${env.VERSION}
            """
        }
        failure {
            echo '❌ Build failed - check the logs'
        }
    }
}
