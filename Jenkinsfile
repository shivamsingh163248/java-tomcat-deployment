pipeline {
    agent {
        label 'tomcat-local'
    }

    options {
        timestamps()
        disableConcurrentBuilds()
        skipDefaultCheckout(true)
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
                    if (!env.CATALINA_HOME || !(env.CATALINA_HOME ==~ /\/[A-Za-z0-9_./-]+/) ||
                            env.CATALINA_HOME.split('/').contains('..')) {
                        error('Configure CATALINA_HOME as an absolute Tomcat path on this Jenkins host without parent-directory segments.')
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
                sh '''
                    set +x
                    set -eu
                    war_file="$WORKSPACE/image.war"
                    webapps_dir="${CATALINA_HOME%/}/webapps"
                    temporary_war="$webapps_dir/.image.war.new-${BUILD_NUMBER}"

                    test -s "$war_file"
                    if [ ! -d "$webapps_dir" ] || [ ! -w "$webapps_dir" ]; then
                        echo "Tomcat webapps directory is missing or not writable: $webapps_dir" >&2
                        exit 1
                    fi
                    if ! command -v curl >/dev/null 2>&1; then
                        echo "curl is required for the Tomcat health check." >&2
                        exit 1
                    fi

                    trap 'rm -f "$temporary_war"' EXIT
                    trap 'exit 1' HUP INT TERM
                    cp "$war_file" "$temporary_war"
                    chmod 0644 "$temporary_war"

                    # Replace only this application's exploded deployment and WAR.
                    rm -rf -- "$webapps_dir/image"
                    mv -f -- "$temporary_war" "$webapps_dir/image.war"

                    attempt=1
                    while [ "$attempt" -le 60 ]; do
                        if curl --connect-timeout 5 --max-time 10 --fail --location \
                                --silent --output /dev/null "$TOMCAT_HEALTH_URL"; then
                            echo "Deployment verified at $TOMCAT_HEALTH_URL"
                            exit 0
                        fi
                        sleep 5
                        attempt=$((attempt + 1))
                    done

                    echo "Tomcat did not report a successful response from $TOMCAT_HEALTH_URL." >&2
                    exit 1
                '''
            }
        }
    }
}
