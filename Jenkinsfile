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
            yaml '''
apiVersion: v1
kind: Pod
metadata:
  labels:
    workload-type: ci-builds
spec:
  imagePullSecrets:
  - name: nexus-registry-credentials
  containers:
  - name: jnlp
    image: jenkins/inbound-agent:3355.v388858a_47b_33-3-jdk21
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi
  - name: alpine
    image: alpine:3.20
    command: ['sleep', '3600']
    workingDir: /home/jenkins/agent/workspace
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
      limits:
        cpu: 200m
        memory: 128Mi
  - name: kaniko
    image: gcr.io/kaniko-project/executor:debug
    command: ['sleep', '3600']
    volumeMounts:
    - name: nexus-creds
      mountPath: /kaniko/.docker
    resources:
      requests:
        cpu: 500m
        memory: 1Gi
      limits:
        cpu: 1000m
        memory: 2Gi
  volumes:
  - name: nexus-creds
    secret:
      secretName: nexus-registry-credentials
'''
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
            // No branch condition needed - job is configured to only pull from main
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
            // No branch condition needed - job is configured to only pull from main
            steps {
                container('alpine') {
                    withCredentials([usernamePassword(
                        credentialsId: 'github-app',
                        usernameVariable: 'GIT_USER',
                        passwordVariable: 'GIT_TOKEN'
                    )]) {
                        script {
                            sh 'apk add --no-cache git curl jq'

                            // Get current version info
                            def currentTag = sh(
                                script: "git describe --tags --abbrev=0 2>/dev/null || echo 'v0.0.0'",
                                returnStdout: true
                            ).trim()

                            // Calculate next pre-release version
                            def baseVersion = currentTag.replaceAll(/-rc\..*/, '')
                            // Use findAll to avoid serialization issues with Matcher
                            def rcMatches = (currentTag =~ /-rc\.(\d+)/).findAll()
                            def rcNum = rcMatches ? (rcMatches[0][1] as int) + 1 : 1

                            // If the current tag is a stable release, bump minor
                            if (!currentTag.contains('-rc.')) {
                                def parts = baseVersion.replace('v', '').tokenize('.')
                                def major = parts[0] as int
                                def minor = parts[1] as int
                                baseVersion = "v${major}.${minor + 1}.0"
                                rcNum = 1
                            }

                            env.NEW_VERSION = "${baseVersion}-rc.${rcNum}"
                            echo "Creating pre-release: ${env.NEW_VERSION}"

                            // Create and push tag
                            sh """
                                git config user.email "jenkins@erauner.dev"
                                git config user.name "Jenkins CI"
                                git tag -a ${env.NEW_VERSION} -m "Pre-release ${env.NEW_VERSION}"
                                git remote set-url origin https://\${GIT_USER}:\${GIT_TOKEN}@github.com/erauner/homelab-validation-image.git
                                git push origin ${env.NEW_VERSION}
                            """

                            // Create GitHub pre-release
                            def releasePayload = """{
                                "tag_name": "${env.NEW_VERSION}",
                                "name": "${env.NEW_VERSION}",
                                "body": "Pre-release ${env.NEW_VERSION}\\n\\nImage: ${env.IMAGE_NAME}:${env.VERSION}",
                                "draft": false,
                                "prerelease": true
                            }"""

                            writeFile file: 'release-payload.json', text: releasePayload

                            sh """
                                curl -sf -X POST \\
                                    -H "Authorization: token \${GIT_TOKEN}" \\
                                    -H "Accept: application/vnd.github.v3+json" \\
                                    -d @release-payload.json \\
                                    "https://api.github.com/repos/erauner/homelab-validation-image/releases"
                            """
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
