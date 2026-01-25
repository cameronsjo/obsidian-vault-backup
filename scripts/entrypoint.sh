#!/bin/bash
set -euo pipefail

# Obsidian Vault Backup - Entrypoint
# Initializes git/restic, starts watcher and health server

log() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $1"
}

log "Starting Obsidian Vault Backup sidecar"

# Validate required environment variables
: "${AZURE_ACCOUNT_NAME:?AZURE_ACCOUNT_NAME is required}"
: "${AZURE_ACCOUNT_KEY:?AZURE_ACCOUNT_KEY is required}"
: "${RESTIC_REPOSITORY:?RESTIC_REPOSITORY is required}"
: "${RESTIC_PASSWORD:?RESTIC_PASSWORD is required}"

# Export for restic
export AZURE_ACCOUNT_NAME
export AZURE_ACCOUNT_KEY
export RESTIC_REPOSITORY
export RESTIC_PASSWORD

# Set defaults
DEBOUNCE_SECONDS="${DEBOUNCE_SECONDS:-300}"
HEALTH_PORT="${HEALTH_PORT:-8080}"
GIT_USER_NAME="${GIT_USER_NAME:-Obsidian Backup}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-backup@local}"
VAULT_PATH="${VAULT_PATH:-/vault}"

# State directory for health tracking
STATE_DIR="/app/state"
mkdir -p "$STATE_DIR"

# Initialize state files
echo "0" > "$STATE_DIR/last_commit"
echo "0" > "$STATE_DIR/last_backup"
echo "0" > "$STATE_DIR/last_change"
echo "false" > "$STATE_DIR/pending_changes"

log "Checking vault directory: $VAULT_PATH"
if [ ! -d "$VAULT_PATH" ]; then
    log "ERROR: Vault directory does not exist: $VAULT_PATH"
    exit 1
fi

# Check if vault is writable
if ! touch "$VAULT_PATH/.backup-write-test" 2>/dev/null; then
    log "ERROR: Vault directory is not writable: $VAULT_PATH"
    log "The backup service requires write access to create git commits"
    log "Remove ':ro' from the volume mount in your compose file"
    exit 1
fi
rm -f "$VAULT_PATH/.backup-write-test"

# Initialize git repository if needed
cd "$VAULT_PATH"

# Mark directory as safe (required for Git 2.35.2+ when running as different user)
git config --global --add safe.directory "$VAULT_PATH"

if [ ! -d ".git" ]; then
    log "Initializing git repository in vault"
    git init

    # Create .gitignore if it doesn't exist
    if [ ! -f ".gitignore" ]; then
        log "Creating .gitignore"
        cat > .gitignore << 'EOF'
# Obsidian workspace files (change frequently, not useful to track)
.obsidian/workspace.json
.obsidian/workspace-mobile.json
.obsidian/workspaces.json

# Trash
.trash/

# System files
.DS_Store
Thumbs.db

# Backup test files
.backup-write-test
EOF
    fi
fi

# Configure git
git config user.name "$GIT_USER_NAME"
git config user.email "$GIT_USER_EMAIL"
git config core.autocrlf input
git config core.safecrlf false

log "Git configured: $GIT_USER_NAME <$GIT_USER_EMAIL>"

# Check if restic repository exists, initialize if needed
log "Checking restic repository: $RESTIC_REPOSITORY"
if ! restic snapshots --quiet 2>/dev/null; then
    log "Restic repository not found or not initialized"
    log "Run 'docker exec <container> restic init' to initialize"
    log "Continuing without backup functionality until initialized"
fi

# Export environment for child scripts
export DEBOUNCE_SECONDS
export HEALTH_PORT
export VAULT_PATH
export STATE_DIR

log "Starting health server on port $HEALTH_PORT"
/app/health-server.sh &

log "Starting file watcher with ${DEBOUNCE_SECONDS}s debounce"
exec /app/watcher.sh
