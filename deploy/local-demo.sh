#!/usr/bin/env bash
# Rehearse deploy + rollback on your own machine with real Docker (no VPS, no GitHub).
# Builds two versions of the image, deploys v1, deploys v2, then rolls back to v1
# using the same deploy.sh and rollback.sh the pipeline runs on the server.
#
#   bash deploy/local-demo.sh          then open http://localhost:9081/health
set -euo pipefail
cd "$(dirname "$0")/.."

export APP_NAME=tidewater-departures-demo APP_PORT=9081
STATE_DIR="$(mktemp -d)"; export STATE_DIR

step()   { printf '\n==== %s ====\n' "$*"; }
health() { printf '>> http://localhost:%s/health says: ' "$APP_PORT"; curl -s "http://127.0.0.1:${APP_PORT}/health"; echo; }

step "build two versions of the image"
docker build -q --build-arg APP_VERSION=demo-v1 -t tidewater-departures:demo-v1 . >/dev/null
docker build -q --build-arg APP_VERSION=demo-v2 -t tidewater-departures:demo-v2 . >/dev/null
echo "built tidewater-departures:demo-v1 and tidewater-departures:demo-v2"
docker rm -f "$APP_NAME" >/dev/null 2>&1 || true

step "deploy v1";          bash deploy/deploy.sh tidewater-departures:demo-v1; health
step "deploy v2";          bash deploy/deploy.sh tidewater-departures:demo-v2; health
step "one-step rollback";  bash deploy/rollback.sh;                    health

printf '\nv1 is running again. Open http://localhost:%s/health in a browser to see it.\n' "$APP_PORT"
printf 'Clean up afterwards with: docker rm -f %s\n' "$APP_NAME"
