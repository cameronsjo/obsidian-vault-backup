#!/bin/bash
set -euo pipefail

# Obsidian Vault Backup - File Watcher
# Monitors vault for changes with debounce, triggers backup

log() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [watcher] $1"
}

VAULT_PATH="${VAULT_PATH:-/vault}"
DEBOUNCE_SECONDS="${DEBOUNCE_SECONDS:-300}"
STATE_DIR="${STATE_DIR:-/app/state}"

# Track last activity time
LAST_ACTIVITY=0
PENDING=false

log "Watching $VAULT_PATH with ${DEBOUNCE_SECONDS}s debounce"

# Cleanup function
cleanup() {
    log "Shutting down watcher"
    exit 0
}
trap cleanup SIGTERM SIGINT

# Function to check if debounce period has elapsed
check_and_backup() {
    if [ "$PENDING" = true ]; then
        local now
        now=$(date +%s)
        local elapsed=$((now - LAST_ACTIVITY))

        if [ "$elapsed" -ge "$DEBOUNCE_SECONDS" ]; then
            log "Debounce period elapsed (${elapsed}s >= ${DEBOUNCE_SECONDS}s), triggering backup"
            PENDING=false
            echo "false" > "$STATE_DIR/pending_changes"

            # Run backup in background so we don't miss events
            /app/backup.sh &
        fi
    fi
}

# Start inotifywait in monitor mode
# Watch for modifications, creates, deletes, and moves
# Exclude .git directory and workspace files
inotifywait \
    --monitor \
    --recursive \
    --event modify,create,delete,move \
    --exclude '(\.git|workspace.*\.json)' \
    --format '%w%f %e' \
    "$VAULT_PATH" 2>/dev/null | while read -r line; do

    # Update last activity time
    LAST_ACTIVITY=$(date +%s)
    echo "$LAST_ACTIVITY" > "$STATE_DIR/last_change"

    if [ "$PENDING" = false ]; then
        log "Change detected: $line"
        log "Starting ${DEBOUNCE_SECONDS}s debounce timer"
        PENDING=true
        echo "true" > "$STATE_DIR/pending_changes"
    fi
done &

INOTIFY_PID=$!

# Main loop - check debounce timer periodically
while true; do
    # Read pending state from file (shared with inotifywait subshell)
    if [ -f "$STATE_DIR/pending_changes" ]; then
        PENDING=$(cat "$STATE_DIR/pending_changes")
    fi

    if [ -f "$STATE_DIR/last_change" ]; then
        LAST_ACTIVITY=$(cat "$STATE_DIR/last_change")
    fi

    check_and_backup

    # Check every 10 seconds
    sleep 10

    # Verify inotifywait is still running
    if ! kill -0 "$INOTIFY_PID" 2>/dev/null; then
        log "ERROR: inotifywait process died, restarting"
        exec /app/watcher.sh
    fi
done
