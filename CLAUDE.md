# Obsidian Vault Backup

A lightweight sidecar container that automatically backs up Obsidian vaults with git versioning and restic cloud storage.

## Quick Reference

```bash
# Run locally (requires vault path)
VAULT_PATH=/path/to/vault python -m vault_backup

# Run tests
pytest

# Lint
ruff check src/
ruff format src/

# Build container
docker build -t vault-backup .
```

## Architecture

```
Watchdog (file monitor) -> Debounce (5min) -> Git Commit -> Restic Backup -> Notify
                                                  |
                                             Claude Haiku
                                          (AI commit messages)
```

**Key modules:**

- `__main__.py` - Entry point, initialization, signal handling
- `watcher.py` - File system monitoring with watchdog
- `backup.py` - Git commit and restic backup logic
- `config.py` - Environment variable configuration
- `health.py` - HTTP health endpoint server
- `notify.py` - Discord/Slack/webhook notifications

## Key Decisions

- **Python 3.12+** - Modern Python with type hints throughout
- **Alpine container** - Minimal image size (~50MB)
- **Watchdog** - Cross-platform file monitoring
- **Restic** - Deduplicated, encrypted backups
- **Claude Haiku** - Optional AI commit messages from file changes

## Environment Variables

Required: `RESTIC_REPOSITORY`, `RESTIC_PASSWORD`, plus backend-specific vars (Azure, S3, B2).

Optional: `ANTHROPIC_API_KEY` for AI commits, `DISCORD_WEBHOOK_URL`/`SLACK_WEBHOOK_URL` for notifications.

## Testing

Tests use pytest. Test files should go in `tests/` directory.

```bash
pytest -v                 # Run all tests
pytest --cov=vault_backup # With coverage
```
