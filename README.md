# Obsidian Vault Backup

Sidecar container that watches an Obsidian vault for changes, commits to git, and backs up to cloud storage via restic.

## Features

- **File watching** - inotify-based monitoring with configurable debounce
- **Git versioning** - Auto-commits changes with optional AI-generated messages
- **Cloud backup** - Restic to Azure Blob Storage (or any restic-supported backend)
- **Health endpoint** - HTTP `/health` endpoint for monitoring
- **Retention policy** - 7 daily, 4 weekly, 12 monthly snapshots
- **Notifications** - Discord webhook alerts on backup success/failure

## Quick Start

```yaml
services:
  obsidian-vault-backup:
    image: ghcr.io/cameronsjo/obsidian-vault-backup:latest
    environment:
      TZ: America/Chicago
      VAULT_PATH: /vault
      DEBOUNCE_SECONDS: 300
      # Azure Storage
      AZURE_ACCOUNT_NAME: your-account
      AZURE_ACCOUNT_KEY: your-key
      RESTIC_REPOSITORY: azure:container-name:/obsidian
      RESTIC_PASSWORD: your-restic-password
      # Optional: AI commit messages
      ANTHROPIC_API_KEY: sk-ant-...
      ANTHROPIC_MODEL: claude-haiku-4-5-latest
      # Optional: Discord notifications
      DISCORD_WEBHOOK_URL: https://discord.com/api/webhooks/...
    volumes:
      - /path/to/vault:/vault  # Must be writable (no :ro)
    ports:
      - "8080:8080"
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `AZURE_ACCOUNT_NAME` | Yes | - | Azure storage account name |
| `AZURE_ACCOUNT_KEY` | Yes | - | Azure storage account key |
| `RESTIC_REPOSITORY` | Yes | - | Restic repository URL |
| `RESTIC_PASSWORD` | Yes | - | Restic encryption password |
| `VAULT_PATH` | No | `/vault` | Path to Obsidian vault |
| `DEBOUNCE_SECONDS` | No | `300` | Wait time after last change before backup |
| `HEALTH_PORT` | No | `8080` | Health endpoint port |
| `GIT_USER_NAME` | No | `Obsidian Backup` | Git commit author name |
| `GIT_USER_EMAIL` | No | `backup@local` | Git commit author email |
| `ANTHROPIC_API_KEY` | No | - | Anthropic API key for AI commit messages |
| `ANTHROPIC_MODEL` | No | `claude-haiku-4-5-latest` | Model for commit messages |
| `LLM_API_URL` | No | - | OpenAI-compatible API URL (alternative to Anthropic) |
| `LLM_API_KEY` | No | - | API key for OpenAI-compatible endpoint |
| `LLM_MODEL` | No | `anthropic/claude-haiku-4.5` | Model for OpenAI-compatible API |
| `DISCORD_WEBHOOK_URL` | No | - | Discord webhook for backup notifications |

## Health Endpoint

```bash
curl http://localhost:8080/health
```

```json
{
  "status": "healthy",
  "last_commit": "2024-01-15T10:30:00Z",
  "last_backup": "2024-01-15T10:30:15Z",
  "last_change": "2024-01-15T10:25:00Z",
  "pending_changes": false,
  "commits_since_backup": 0
}
```

Status is `unhealthy` if changes exist but no backup in 24 hours.

## Initial Setup

After first run, initialize the restic repository:

```bash
docker exec obsidian-vault-backup restic init
```

## How It Works

```
File Change -> inotify -> Debounce (5min) -> Git Commit -> Restic Backup -> Prune
```

1. **inotifywait** monitors vault for file changes
2. **Debounce timer** waits for inactivity (default 5 minutes)
3. **Git commit** with AI-generated or timestamp message
4. **Restic backup** to Azure (or configured backend)
5. **Prune** old snapshots per retention policy

## Restore

List available snapshots:

```bash
docker exec obsidian-vault-backup restic snapshots
```

Restore to a directory:

```bash
docker exec obsidian-vault-backup restic restore latest --target /restore
```

## License

MIT
