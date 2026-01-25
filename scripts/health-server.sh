#!/bin/bash
set -euo pipefail

# Obsidian Vault Backup - Health Server
# Serves /health endpoint with status metrics

HEALTH_PORT="${HEALTH_PORT:-8080}"
STATE_DIR="${STATE_DIR:-/app/state}"
VAULT_PATH="${VAULT_PATH:-/vault}"

# Create health document directory
HEALTH_DIR="/tmp/health"
mkdir -p "$HEALTH_DIR"

# Function to generate health JSON
generate_health() {
    local now
    now=$(date +%s)

    # Read state files
    local last_commit=0
    local last_backup=0
    local last_change=0
    local pending_changes="false"

    [ -f "$STATE_DIR/last_commit" ] && last_commit=$(cat "$STATE_DIR/last_commit")
    [ -f "$STATE_DIR/last_backup" ] && last_backup=$(cat "$STATE_DIR/last_backup")
    [ -f "$STATE_DIR/last_change" ] && last_change=$(cat "$STATE_DIR/last_change")
    [ -f "$STATE_DIR/pending_changes" ] && pending_changes=$(cat "$STATE_DIR/pending_changes")

    # Convert timestamps to ISO format
    local last_commit_iso="null"
    local last_backup_iso="null"
    local last_change_iso="null"

    [ "$last_commit" -gt 0 ] && last_commit_iso="\"$(date -u -d "@$last_commit" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -r "$last_commit" +"%Y-%m-%dT%H:%M:%SZ")\""
    [ "$last_backup" -gt 0 ] && last_backup_iso="\"$(date -u -d "@$last_backup" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -r "$last_backup" +"%Y-%m-%dT%H:%M:%SZ")\""
    [ "$last_change" -gt 0 ] && last_change_iso="\"$(date -u -d "@$last_change" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -r "$last_change" +"%Y-%m-%dT%H:%M:%SZ")\""

    # Count commits since last backup
    local commits_since_backup=0
    if [ "$last_commit" -gt "$last_backup" ] && [ "$last_backup" -gt 0 ]; then
        commits_since_backup=$(cd "$VAULT_PATH" && git rev-list --count --since="@$last_backup" HEAD 2>/dev/null || echo 0)
    fi

    # Check for sync.json
    local sync_state="null"
    if [ -f "$VAULT_PATH/.obsidian/sync.json" ]; then
        sync_state=$(cat "$VAULT_PATH/.obsidian/sync.json" 2>/dev/null | jq -c '.' || echo "null")
    fi

    # Determine overall status
    local status="healthy"
    local seconds_since_backup=$((now - last_backup))

    # Unhealthy if no backup in 24 hours (and we've had changes)
    if [ "$last_backup" -gt 0 ] && [ "$seconds_since_backup" -gt 86400 ] && [ "$last_change" -gt "$last_backup" ]; then
        status="unhealthy"
    fi

    # Build JSON
    cat << EOF
{
  "status": "$status",
  "last_commit": $last_commit_iso,
  "last_backup": $last_backup_iso,
  "last_change": $last_change_iso,
  "pending_changes": $pending_changes,
  "commits_since_backup": $commits_since_backup,
  "sync_state": $sync_state,
  "uptime_seconds": $((now - $(cat /proc/1/stat | awk '{print $22}') / 100))
}
EOF
}

# Update health file periodically
update_health_loop() {
    while true; do
        generate_health > "$HEALTH_DIR/health"
        sleep 5
    done
}

# Start health update loop in background
update_health_loop &

# Create a simple HTTP response handler
handle_request() {
    local request
    read -r request

    # Parse request
    local method path
    method=$(echo "$request" | awk '{print $1}')
    path=$(echo "$request" | awk '{print $2}')

    # Read headers (discard)
    while read -r header; do
        [ -z "$header" ] || [ "$header" = $'\r' ] && break
    done

    # Generate response
    if [ "$path" = "/health" ] || [ "$path" = "/health/" ]; then
        local body
        body=$(cat "$HEALTH_DIR/health")
        local length=${#body}

        echo -e "HTTP/1.1 200 OK\r"
        echo -e "Content-Type: application/json\r"
        echo -e "Content-Length: $length\r"
        echo -e "Connection: close\r"
        echo -e "\r"
        echo -n "$body"
    else
        local body='{"error": "Not Found"}'
        local length=${#body}

        echo -e "HTTP/1.1 404 Not Found\r"
        echo -e "Content-Type: application/json\r"
        echo -e "Content-Length: $length\r"
        echo -e "Connection: close\r"
        echo -e "\r"
        echo -n "$body"
    fi
}

# Generate initial health file
generate_health > "$HEALTH_DIR/health"

echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [health] Starting HTTP server on port $HEALTH_PORT"

# Use busybox httpd if available, otherwise use nc loop
if command -v httpd &>/dev/null; then
    # Create CGI script for dynamic content
    mkdir -p "$HEALTH_DIR/cgi-bin"
    cat > "$HEALTH_DIR/cgi-bin/health" << 'CGISCRIPT'
#!/bin/sh
echo "Content-Type: application/json"
echo ""
cat /tmp/health/health
CGISCRIPT
    chmod +x "$HEALTH_DIR/cgi-bin/health"

    # Use busybox httpd
    exec httpd -f -p "$HEALTH_PORT" -h "$HEALTH_DIR" -c /dev/null
else
    # Fallback to netcat loop
    while true; do
        echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n$(cat "$HEALTH_DIR/health")" | nc -l -p "$HEALTH_PORT" -q 1 >/dev/null 2>&1 || true
    done
fi
