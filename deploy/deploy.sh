#!/usr/bin/env bash
# Deploy one image and verify it, rolling back automatically if it is unhealthy.
#
#   deploy.sh ghcr.io/<owner>/tidewater-departures:<commit-sha>
#
# State kept in $STATE_DIR:
#   current  - image that is live now
#   previous - image that was live before it (rollback target)
set -euo pipefail
source "$(dirname "$0")/common.sh"

IMAGE="${1:?usage: deploy.sh <image-ref>}"

PREVIOUS="$(running_image)"
log "deploying  : $IMAGE"
log "currently  : ${PREVIOUS:-<nothing running>}"

# Tags are commit SHAs, so an image that is already here is already the right one.
docker image inspect "$IMAGE" >/dev/null 2>&1 || docker pull "$IMAGE"
log "image size: $(docker image inspect -f '{{.Size}}' "$IMAGE" | awk '{printf "%.0f MB", $1/1024/1024}')"
run_container "$IMAGE"

if wait_healthy; then
  if [[ -n "$PREVIOUS" && "$PREVIOUS" != "$IMAGE" ]]; then
    write_state previous "$PREVIOUS"
  fi
  write_state current "$IMAGE"
  log "DEPLOYED $IMAGE (rollback target: $(read_state previous))"
  exit 0
fi

log "new image is unhealthy"
if [[ -n "$PREVIOUS" ]]; then
  log "auto-rollback to $PREVIOUS"
  run_container "$PREVIOUS"
  wait_healthy && log "auto-rollback complete; $PREVIOUS is serving again"
fi
exit 1
