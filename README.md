# Java Tomcat Deployment

A Java 17 Jakarta Servlet application packaged as a WAR and deployed to Apache Tomcat. GitHub Actions builds, tests, and publishes the WAR. Jenkins downloads that exact artifact and deploys it to Tomcat on the **same host**. Jenkins does not build the application.

## Architecture

```text
Developer
   |
   | push to main
   v
GitHub Actions
   |-- Checkout source
   |-- Build and test with Java 17 and Maven
   |-- Package target/image.war
   |-- Upload tomcat-deployment-war
   `-- Trigger Jenkins only after upload succeeds
             |
             | run ID + artifact name
             v
Jenkins on the Tomcat host
   |-- Download the artifact from that exact GitHub Actions run
   |-- Deploy image.war to CATALINA_HOME/webapps
   `-- Check the local application URL
             |
             v
          Apache Tomcat
```

## Application

| Property | Value |
|---|---|
| Java | 17 |
| Maven coordinates | `org.image:Image:1.0-SNAPSHOT` |
| Packaging | WAR |
| WAR file | `target/image.war` |
| Web technology | Jakarta Servlet 6 |
| Test framework | JUnit 5 and Mockito |
| Tomcat version | 10.1 or later |
| Application context | `/image/` |

The original `org.image.Main` console class is preserved. The WAR exposes the greeting through a servlet at the application root.

## Build locally

Install Java 17 and Maven, then run:

```sh
mvn clean verify
```

This validates and compiles the application, runs tests, and creates `target/image.war`.

## GitHub Actions CI

The workflow is [`.github/workflows/ci.yml`](.github/workflows/ci.yml). It runs on pushes to `main` and can also be started manually with `workflow_dispatch`.

On a successful build and test, it verifies `target/image.war`, uploads only that file as the `tomcat-deployment-war` artifact, then triggers the Jenkins job `TomcatDeployment`. Jenkins is not triggered if any preceding CI or artifact-upload step fails.

Add these **repository Actions secrets** under **GitHub → Settings → Secrets and variables → Actions**:

| Secret | Value |
|---|---|
| `JENKINS_TOKEN` | API token for that account |

The workflow has the non-secret Jenkins URL `http://20.219.118.177:8080` and username `shsingh` configured directly in `ci.yml`. The Jenkins account needs permission to read the crumb issuer and start `TomcatDeployment`. CSRF protection must remain enabled; the workflow requests and sends a Jenkins crumb. Before deployment can be triggered, enable HTTPS for Jenkins and change the workflow's `JENKINS_URL` to its HTTPS address. The workflow intentionally refuses to send the API token over plain HTTP.

## Jenkins and Tomcat: same-host setup

Jenkins and Tomcat must be installed on the **same server** for the current local-filesystem deployment. The Jenkins agent that executes this Pipeline must run on that server and have the label `tomcat-local`. No SSH connection or Tomcat SSH credential is used.

### 1. Prepare the server and Jenkins agent

- Install Tomcat 10.1 or later on the same server as Jenkins, and configure it to auto-deploy WAR files from its `webapps` directory.
- Install Jenkins and register an agent on the Tomcat server with the label `tomcat-local`.
- Run the Jenkins agent service as the dedicated operating-system account `shsingh` (or configure that account for the agent service).
- Grant that account write permission only where required to deploy to Tomcat's `webapps` directory. Do not run Jenkins as root.
- Ensure `curl`, `jq`, and `unzip` are available to the Jenkins agent.

### 2. Create the Jenkins job

Create a **Pipeline** job named exactly `TomcatDeployment`:

1. In Jenkins, select **New Item**, enter `TomcatDeployment`, choose **Pipeline**, then select **OK**.
2. In the job configuration's **Pipeline** section, set **Definition** to **Pipeline script from SCM**.
3. Set **SCM** to **Git** and enter the repository URL:
   `https://github.com/shivamsingh163248/java-tomcat-deployment.git`
4. Set the branch specifier to `*/main`. Credentials can be left empty for this public repository.
5. Set **Script Path** to `Jenkinsfile`, then save.

The Jenkinsfile restricts the job to an agent with label `tomcat-local` and skips the default source checkout. Run the job once after configuring it so Jenkins registers the declared parameters; a manual first build without GitHub-provided parameter values may fail validation.

### 3. Add the GitHub artifact credential to Jenkins

Jenkins must authenticate to GitHub to retrieve Actions artifacts, even though this repository is public. Public repository visibility does not make Actions artifacts anonymously downloadable.

Create a fine-grained GitHub token scoped to this repository with **Actions: Read-only** permission. In Jenkins, open **Manage Jenkins → Credentials → System → Global credentials → Add Credentials** and create:

| Setting | Value |
|---|---|
| Kind | Secret text |
| ID | `github-actions-artifact-read-token` |
| Secret | The fine-grained GitHub token |

The token is used only by Jenkins to download the artifact. Do not put it in the Jenkinsfile, workflow, or repository.

### 4. Configure Tomcat environment variables in Jenkins

Set these variables in the environment of the `tomcat-local` Jenkins agent:

| Variable | Example |
|---|---|
| `CATALINA_HOME` | The actual absolute Tomcat installation path, for example `/srv/tomcat` |
| `TOMCAT_HEALTH_URL` | `http://127.0.0.1:8081/image/` if Tomcat uses port `8081` |

Replace the example `CATALINA_HOME` with the path on your server. The supplied URL `http://20.219.118.177:8080/` responds as Jenkins, not Tomcat. Since Jenkins uses port `8080` on this host, configure Tomcat's HTTP connector to use a different available port, for example `8081`. With that example configuration, the application URL is `http://20.219.118.177:8081/image/`, and Jenkins checks it locally at `http://127.0.0.1:8081/image/`. Use the actual port configured for Tomcat and permit it through the server firewall if external access is required.

### Jenkins job parameters

GitHub Actions supplies these parameters to `TomcatDeployment`:

| Parameter | Meaning |
|---|---|
| `GITHUB_REPOSITORY` | Repository that produced the artifact, in `owner/repository` format |
| `GITHUB_RUN_ID` | Exact GitHub Actions run containing the artifact |
| `ARTIFACT_NAME` | `tomcat-deployment-war` |

## Deployment behavior

Jenkins uses the repository and run ID to query the GitHub Actions Artifacts API. It requires exactly one unexpired artifact named `tomcat-deployment-war`, downloads it, and verifies that the archive contains only `image.war`.

The Pipeline then stages the WAR locally, replaces only `${CATALINA_HOME}/webapps/image.war` and its exploded `${CATALINA_HOME}/webapps/image` directory, and waits up to five minutes for an HTTP success response from `TOMCAT_HEALTH_URL`. It does not remove or modify other Tomcat applications. A failed download, validation, filesystem deployment, or health check fails the Jenkins build.

## Test the end-to-end pipeline

1. Configure the GitHub secrets, Jenkins agent/job/credential, Tomcat environment variables, and directory permissions above.
2. Push a commit to `main`, or manually run the **Java CI and Tomcat deployment** GitHub Actions workflow.
3. Confirm CI and tests pass and the `tomcat-deployment-war` artifact is uploaded.
4. Confirm Jenkins starts `TomcatDeployment` with the same `GITHUB_RUN_ID` and reports deployment verification.
5. Open `http://20.219.118.177:8080/image/` to verify the deployed application.

## Troubleshooting and security

- **Jenkins is not triggered:** Check `JENKINS_URL`, `JENKINS_USER`, `JENKINS_TOKEN`, the job name, Jenkins permissions, and crumb endpoint access.
- **Artifact download fails:** Check the `github-actions-artifact-read-token` credential's repository scope and Actions read permission, and verify the run's artifact has not expired. Artifacts are retained for 30 days.
- **No matching agent:** Confirm the Jenkins agent runs on the Tomcat host and has the label `tomcat-local`.
- **Deployment fails:** Confirm `CATALINA_HOME`, the agent account's `webapps` write permission, Tomcat auto-deployment, and Tomcat logs.
- **Health check times out:** Confirm the application URL, Tomcat HTTP connector port, and local connectivity to `127.0.0.1`.

Keep tokens and passwords out of source control. Use least-privilege GitHub/Jenkins credentials, do not run Jenkins as root, and keep Jenkins CSRF protection enabled. If a real token or password has been exposed in a chat or committed, revoke or rotate it.

Jenkins, GitHub secrets/credentials, the same-host agent, and Tomcat must be configured manually; this repository cannot provision those services.
