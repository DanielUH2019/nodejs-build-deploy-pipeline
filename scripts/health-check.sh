#!/usr/bin/env bash
#
# health-check.sh — poll the deployed service until it answers correctly.
#
# Runs ON THE JENKINS AGENT after the SSH deploy. Retries with a delay because a
# freshly (re)started service needs a moment to come up. Exits 0 on the first
# healthy response, non-zero if it never becomes healthy within the budget.
#
# Inputs (exported by the Jenkins pipeline):
#   TARGET_HOST                - host the service runs on
#   APP_PORT                   - TCP port the service listens on
#   HEALTH_CHECK_RETRIES       - max number of attempts
#   HEALTH_CHECK_SLEEP_SECONDS - delay between attempts
set -euo pipefail

: "${TARGET_HOST:?TARGET_HOST must be set}"
: "${APP_PORT:?APP_PORT must be set}"
: "${HEALTH_CHECK_RETRIES:?HEALTH_CHECK_RETRIES must be set}"
: "${HEALTH_CHECK_SLEEP_SECONDS:?HEALTH_CHECK_SLEEP_SECONDS must be set}"

url="http://$TARGET_HOST:$APP_PORT/"
echo "Health-checking $url (up to $HEALTH_CHECK_RETRIES attempts) ..."

attempt=1
while [ "$attempt" -le "$HEALTH_CHECK_RETRIES" ]; do
    # `curl -f` fails on HTTP >= 400. Express's res.json() emits lowercase keys:
    # {"name":"Hello","description":"World","url":"..."}
    if response="$(curl -fsS "$url")" \
        && printf '%s' "$response" | grep -q '"name":"Hello"' \
        && printf '%s' "$response" | grep -q '"description":"World"'; then
        echo "Health check passed on attempt $attempt:"
        echo "$response"
        exit 0
    fi

    echo "Attempt $attempt/$HEALTH_CHECK_RETRIES failed; retrying in ${HEALTH_CHECK_SLEEP_SECONDS}s"
    sleep "$HEALTH_CHECK_SLEEP_SECONDS"
    attempt=$((attempt + 1))
done

echo "Health check failed after $HEALTH_CHECK_RETRIES attempts against $url" >&2
exit 1
