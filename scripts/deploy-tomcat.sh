#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "Usage: deploy-tomcat.sh /path/to/image.war" >&2
    exit 2
fi

war_file=$1
if [ ! -s "$war_file" ] || [ "${war_file##*/}" != "image.war" ]; then
    echo "Expected a non-empty image.war deployment artifact." >&2
    exit 1
fi

: "${CATALINA_HOME:?CATALINA_HOME must point to the Tomcat installation}"
: "${TOMCAT_HEALTH_URL:?TOMCAT_HEALTH_URL must point to the deployed /image application}"

case "$CATALINA_HOME" in
    /*) ;;
    *) echo "CATALINA_HOME must be an absolute path." >&2; exit 1 ;;
esac
case "$TOMCAT_HEALTH_URL" in
    http://*|https://*) ;;
    *) echo "TOMCAT_HEALTH_URL must use HTTP or HTTPS." >&2; exit 1 ;;
esac

webapps_dir="${CATALINA_HOME%/}/webapps"
if [ ! -d "$webapps_dir" ] || [ ! -w "$webapps_dir" ]; then
    echo "Tomcat webapps directory is missing or not writable: $webapps_dir" >&2
    exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required on the Tomcat host for deployment verification." >&2
    exit 1
fi

temporary_war="$webapps_dir/.image.war.new"
trap 'rm -f "$temporary_war"' EXIT
trap 'exit 1' HUP INT TERM
cp "$war_file" "$temporary_war"
chmod 0644 "$temporary_war"

# Remove only this application's exploded deployment; Tomcat redeploys the new WAR.
rm -rf -- "$webapps_dir/image"
mv -f -- "$temporary_war" "$webapps_dir/image.war"

attempt=1
while [ "$attempt" -le 60 ]; do
    if curl --connect-timeout 5 --max-time 10 --fail --location --silent --output /dev/null "$TOMCAT_HEALTH_URL"; then
        echo "Deployment verified at $TOMCAT_HEALTH_URL"
        exit 0
    fi
    sleep 5
    attempt=$((attempt + 1))
done

echo "Tomcat did not report a successful response from $TOMCAT_HEALTH_URL." >&2
exit 1
