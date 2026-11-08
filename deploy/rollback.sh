#!/usr/bin/env bash
# One-step rollback: put the previously deployed image back and verify it.
#
#   rollback.sh                 # roll back to the image recorded as "previous"
#   rollback.sh <image-ref>     # roll back (or forward) to a specific image
set -euo pipefail
source "$(dirname "$0")/common.sh"

TARGET="${1:-$(read_state previous)}"
CURRENT="$(read_state current)"

if [[ -z "$TARGET" ]]; then
  log "no previous image recorded in $STATE_DIR/previous and none given"
  exit 1
fi
if [[ "$TARGET" == "$CURRENT" ]]; then
  log "$TARGET is already the current image - nothing to do"
  exit 0
fi

log "rolling back: $CURRENT  ->  $TARGET"
run_container "$TARGET"
wait_healthy

# Swap the pointers so a second rollback undoes this one (roll forward).
write_state current "$TARGET"
if [[ -n "$CURRENT" ]]; then
  write_state previous "$CURRENT"
fi
log "ROLLED BACK to $TARGET (roll-forward target: $CURRENT)"
