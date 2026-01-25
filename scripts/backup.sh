#!/bin/bash
set -euo pipefail

# Obsidian Vault Backup - Backup Script
# Commits changes to git, backs up to restic

log() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [backup] $1"
}

VAULT_PATH="${VAULT_PATH:-/vault}"
STATE_DIR="${STATE_DIR:-/app/state}"

cd "$VAULT_PATH"

# Check for changes
if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
    log "No changes to commit"
    exit 0
fi

# Stage all changes
log "Staging changes"
git add -A

# Count changes
CHANGES=$(git diff --cached --stat | tail -n 1 || echo "files changed")
CHANGED_FILES=$(git diff --cached --name-only)
TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

# Generate commit message
COMMIT_MSG=""

# Try AI-generated message if LLM is configured
# Supports: Anthropic API (ANTHROPIC_API_KEY) or OpenAI-compatible (LLM_API_URL)
if [ -n "${ANTHROPIC_API_KEY:-}" ] || [ -n "${LLM_API_URL:-}" ]; then
    log "Generating AI commit message"

    # Build prompt with changed filenames (not content for privacy)
    PROMPT="Summarize these Obsidian vault changes in one concise commit message line (max 60 chars). Be specific about what changed based on filenames. Use lowercase, no period at end.

Changed files:
$CHANGED_FILES

Stats: $CHANGES"

    if [ -n "${LLM_API_URL:-}" ]; then
        # OpenAI-compatible API (Agentgateway, OpenRouter, etc.)
        LLM_MODEL="${LLM_MODEL:-anthropic/claude-3.5-haiku}"
        log "Using OpenAI-compatible API: $LLM_API_URL (model: $LLM_MODEL)"

        REQUEST_BODY=$(jq -n \
            --arg model "$LLM_MODEL" \
            --arg prompt "$PROMPT" \
            '{
                model: $model,
                max_tokens: 100,
                messages: [{role: "user", content: $prompt}]
            }')

        AI_RESPONSE=$(curl -s --max-time 10 "$LLM_API_URL" \
            -H "Content-Type: application/json" \
            ${LLM_API_KEY:+-H "Authorization: Bearer $LLM_API_KEY"} \
            -d "$REQUEST_BODY" 2>/dev/null)

        AI_MSG=$(echo "$AI_RESPONSE" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
    else
        # Anthropic native API
        ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-claude-sonnet-4-20250514}"
        ANTHROPIC_API_URL="${ANTHROPIC_API_URL:-https://api.anthropic.com/v1/messages}"
        log "Using Anthropic API (model: $ANTHROPIC_MODEL)"

        REQUEST_BODY=$(jq -n \
            --arg model "$ANTHROPIC_MODEL" \
            --arg prompt "$PROMPT" \
            '{
                model: $model,
                max_tokens: 100,
                messages: [{role: "user", content: $prompt}]
            }')

        AI_RESPONSE=$(curl -s --max-time 10 "$ANTHROPIC_API_URL" \
            -H "Content-Type: application/json" \
            -H "x-api-key: $ANTHROPIC_API_KEY" \
            -H "anthropic-version: 2023-06-01" \
            -d "$REQUEST_BODY" 2>/dev/null)

        AI_MSG=$(echo "$AI_RESPONSE" | jq -r '.content[0].text // empty' 2>/dev/null)
    fi

    if [ -n "$AI_MSG" ]; then
        COMMIT_MSG="vault: $AI_MSG"
        log "AI message: $AI_MSG"
    else
        log "AI generation failed, using fallback"
        log "Response: $(echo "$AI_RESPONSE" | jq -c '.' 2>/dev/null || echo "$AI_RESPONSE")"
    fi
fi

# Fallback to basic message
if [ -z "$COMMIT_MSG" ]; then
    COMMIT_MSG="vault: auto-backup $TIMESTAMP

$CHANGES"
fi

log "Creating commit: $TIMESTAMP"
if git commit -m "$COMMIT_MSG"; then
    log "Commit created successfully"
    date +%s > "$STATE_DIR/last_commit"
else
    log "ERROR: Failed to create commit"
    exit 1
fi

# Backup to restic
log "Starting restic backup"

# Check if restic repo is initialized
if ! restic snapshots --quiet 2>/dev/null; then
    log "WARNING: Restic repository not initialized, skipping backup"
    log "Run 'docker exec <container> restic init' to initialize"
    exit 0
fi

# Run restic backup
if restic backup \
    --tag obsidian \
    --tag auto-backup \
    --exclude '.git' \
    --verbose \
    "$VAULT_PATH"; then

    log "Restic backup completed successfully"
    date +%s > "$STATE_DIR/last_backup"

    # Prune old backups (keep last 7 daily, 4 weekly, 12 monthly)
    log "Pruning old backups"
    restic forget \
        --tag obsidian \
        --keep-daily 7 \
        --keep-weekly 4 \
        --keep-monthly 12 \
        --prune \
        --quiet

    log "Backup and prune completed"
else
    log "ERROR: Restic backup failed"
    exit 1
fi
