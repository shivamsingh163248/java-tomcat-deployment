pipeline {
    agent any

    options {
        timestamps()
    }

    parameters {
        string(name: 'GITHUB_REPOSITORY', defaultValue: '', description: 'owner/repository that produced the artifact')
        string(name: 'GITHUB_RUN_ID', defaultValue: '', description: 'GitHub Actions run ID containing the artifact')
        string(name: 'ARTIFACT_NAME', defaultValue: 'tomcat-deployment-war', description: 'GitHub Actions artifact name')
    }

    stages {
        stage('Validate deployment parameters') {
            steps {
                script {
                    if (!(params.GITHUB_REPOSITORY ==~ /[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+/)) {
                        error('GITHUB_REPOSITORY must be an owner/repository value.')
                    }
                    if (!(params.GITHUB_RUN_ID ==~ /[0-9]+/)) {
                        error('GITHUB_RUN_ID must contain only digits.')
                    }
                    if (params.ARTIFACT_NAME != 'tomcat-deployment-war') {
                        error('ARTIFACT_NAME must be tomcat-deployment-war.')
                    }
                    if (!env.TOMCAT_HOST || !(env.TOMCAT_HOST ==~ /[A-Za-z0-9.-]+/)) {
                        error('Configure TOMCAT_HOST as a DNS name or IPv4 address in Jenkins.')
                    }
                    if (!env.TOMCAT_SSH_PORT || !(env.TOMCAT_SSH_PORT ==~ /[0-9]+/) ||
                            env.TOMCAT_SSH_PORT.toInteger() < 1 || env.TOMCAT_SSH_PORT.toInteger() > 65535) {
                        error('Configure TOMCAT_SSH_PORT as a valid SSH port in Jenkins.')
                    }
                    if (!env.CATALINA_HOME || !(env.CATALINA_HOME ==~ /\/[A-Za-z0-9_./-]+/) ||
                            env.CATALINA_HOME.split('/').contains('..')) {
                        error('Configure CATALINA_HOME as an absolute Tomcat path without parent-directory segments.')
                    }
                    if (!env.TOMCAT_REMOTE_TMP || !(env.TOMCAT_REMOTE_TMP ==~ /\/[A-Za-z0-9_./-]+/) ||
                            env.TOMCAT_REMOTE_TMP.split('/').contains('..')) {
                        error('Configure TOMCAT_REMOTE_TMP as an absolute temporary directory without parent-directory segments.')
                    }
                    if (!env.TOMCAT_HEALTH_URL ||
                            !(env.TOMCAT_HEALTH_URL ==~ /https?:\/\/[A-Za-z0-9.-]+(:[0-9]+)?\/image\/?/)) {
                        error('Configure TOMCAT_HEALTH_URL as the HTTP(S) URL for the /image application.')
                    }
                }
            }
        }

        stage('Download artifact from this GitHub run') {
            steps {
                withCredentials([string(credentialsId: 'github-actions-artifact-read-token', variable: 'GITHUB_TOKEN')]) {
                    sh '''
                        set +x
                        set -eu
                        umask 077
                        work="$(mktemp -d)"
                        trap 'rm -rf "$work"' EXIT
                        curl_config="$work/github-curl.conf"
                        printf 'header = "Accept: application/vnd.github+json"\n' > "$curl_config"
                        printf 'header = "X-GitHub-Api-Version: 2022-11-28"\n' >> "$curl_config"
                        printf 'header = "Authorization: Bearer %s"\n' "$GITHUB_TOKEN" >> "$curl_config"

                        api_url="https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}/artifacts?name=${ARTIFACT_NAME}"
                        artifacts="$(curl --config "$curl_config" --fail --silent --show-error "$api_url")"
                        artifact_count="$(printf '%s' "$artifacts" | jq --arg name "$ARTIFACT_NAME" \
                            '[.artifacts[] | select(.name == $name and .expired == false)] | length')"
                        if [ "$artifact_count" != "1" ]; then
                            echo "Expected exactly one unexpired artifact named $ARTIFACT_NAME for run $GITHUB_RUN_ID." >&2
                            exit 1
                        fi
                        artifact_id="$(printf '%s' "$artifacts" | jq -er --arg name "$ARTIFACT_NAME" \
                            '.artifacts[] | select(.name == $name and .expired == false) | .id')"

                        curl --config "$curl_config" --fail --silent --show-error --location \
                            "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/artifacts/${artifact_id}/zip" \
                            --output "$work/artifact.zip"
                        entries="$(unzip -Z1 "$work/artifact.zip")"
                        if [ "$entries" != "image.war" ]; then
                            echo "The deployment artifact must contain only image.war." >&2
                            exit 1
                        fi
                        mkdir "$work/extracted"
                        unzip -q "$work/artifact.zip" -d "$work/extracted"
                        test -s "$work/extracted/image.war"
                        cp "$work/extracted/image.war" "$WORKSPACE/image.war"
                    '''
                }
            }
        }

        stage('Deploy WAR to Tomcat') {
            steps {
                withCredentials([sshUserPrivateKey(
                    credentialsId: 'tomcat-deploy-ssh',
                    keyFileVariable: 'TOMCAT_SSH_KEY',
                    usernameVariable: 'TOMCAT_USER'
                )]) {
                    sh '''
                        set +x
                        set -eu
                        remote_dir="${TOMCAT_REMOTE_TMP%/}/tomcat-deploy-${BUILD_NUMBER}"
                        target="${TOMCAT_USER}@${TOMCAT_HOST}"

                        ssh -i "$TOMCAT_SSH_KEY" -o BatchMode=yes -p "$TOMCAT_SSH_PORT" "$target" \
                            "mkdir -p -- $remote_dir"
                        scp -i "$TOMCAT_SSH_KEY" -o BatchMode=yes -P "$TOMCAT_SSH_PORT" \
                            "$WORKSPACE/image.war" "$WORKSPACE/scripts/deploy-tomcat.sh" \
                            "$target:$remote_dir/"
                        ssh -i "$TOMCAT_SSH_KEY" -o BatchMode=yes -p "$TOMCAT_SSH_PORT" "$target" \
                            "CATALINA_HOME=$CATALINA_HOME TOMCAT_HEALTH_URL=$TOMCAT_HEALTH_URL sh $remote_dir/deploy-tomcat.sh $remote_dir/image.war"
                        ssh -i "$TOMCAT_SSH_KEY" -o BatchMode=yes -p "$TOMCAT_SSH_PORT" "$target" \
                            "rm -rf -- $remote_dir"
                    '''
                }
            }
        }
    }
}
