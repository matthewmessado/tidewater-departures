#!/usr/bin/env bash
# Shared helpers for deploy.sh and rollback.sh. Sourced, not executed.
# Everything is overridable through the environment so the same scripts work
# on the Azure VM, another server or a laptop.
#
# The pipeline passes APP_NAME and APP_PORT in; the defaults below are for
# running the scripts by hand on the VM, so keep them in step with the env
# block at the top of the workflow files.

APP_NAME="${APP_NAME:-tidewater-departures}"
APP_PORT="${APP_PORT:-8081}"
APP_DIR="${APP_DIR:-/opt/$APP_NAME}"
STATE_DIR="${STATE_DIR:-$APP_DIR/state}"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:${APP_PORT}/health}"
HEALTH_RETRIES="${HEALTH_RETRIES:-20}"

mkdir -p "$STATE_DIR"

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

# Image reference the running container was started from ("" if none).
running_image() {
  docker inspect -f '{{.Config.Image}}' "$APP_NAME" 2>/dev/null || true
}

# Replace the container with one running $1. Keeps the same name and port so
# nothing upstream (firewall, proxy, bookmarks) has to change.
run_container() {
  local image="$1"
  if ! docker image inspect "$image" >/dev/null 2>&1; then
    log "pulling $image"
    docker pull "$image"
  fi
  docker rm -f "$APP_NAME" >/dev/null 2>&1 || true
  docker run -d \
    --name "$APP_NAME" \
    --restart unless-stopped \
    -p "${APP_PORT}:8080" \
    "$image" >/dev/null
  log "started $APP_NAME from $image on port $APP_PORT"
}

# Poll /health until it answers 200 or we run out of retries.
wait_healthy() {
  local i body
  for ((i = 1; i <= HEALTH_RETRIES; i++)); do
    if body="$(curl -fsS --max-time 2 "$HEALTH_URL" 2>/dev/null)"; then
      log "health check passed: $body"
      return 0
    fi
    sleep 1
  done
  log "health check FAILED after ${HEALTH_RETRIES}s - last 30 log lines:"
  docker logs --tail 30 "$APP_NAME" 2>&1 | sed 's/^/    /' || true
  return 1
}

read_state() { cat "$STATE_DIR/$1" 2>/dev/null || true; }
write_state() { printf '%s\n' "$2" > "$STATE_DIR/$1"; }
