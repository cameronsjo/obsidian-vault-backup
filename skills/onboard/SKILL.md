---
name: obsidi-backup
description: "Get started with obsidi-backup — what it is, how to set it up, and how to use it"
---


Guide the user through getting started with **obsidi-backup**.

## About

obsidi-backup is a lightweight sidecar container that automatically backs up Obsidian vaults with git versioning and encrypted cloud storage via restic. It watches for file changes, auto-commits with optional AI-generated messages (Claude Haiku), and pushes deduplicated backups to Azure, S3, B2, or any restic backend.

## Prerequisites

Check that the user has the following installed/configured:

- Python 3.12+
- uv (Python package manager)
- Docker (for container builds and running)
- restic (for backup operations)
- git
- An Anthropic API key (optional, for AI commit messages)
- A cloud storage backend configured (Azure, S3, B2, SFTP, or local)
- `RESTIC_REPOSITORY` and `RESTIC_PASSWORD` environment variables set

## Setup

Walk the user through initial setup:

1. Clone the repo and install dev dependencies:
   ```bash
   uv pip install -e ".[dev]"
   ```
2. Set required environment variables:
   ```bash
   export RESTIC_REPOSITORY="azure:container:/path"  # or s3, b2, sftp, local
   export RESTIC_PASSWORD="your-encryption-password"
   export VAULT_PATH="/path/to/your/obsidian/vault"
   ```
3. Optionally set AI commit message vars:
   ```bash
   export ANTHROPIC_API_KEY="sk-ant-..."
   ```
4. For container usage, build the image:
   ```bash
   docker build -t vault-backup .
   ```

## First Use

Guide the user through their first interaction with the product:

1. Run locally against a vault:
   ```bash
   VAULT_PATH=/path/to/vault RESTIC_REPOSITORY=... RESTIC_PASSWORD=... python -m vault_backup
   ```
2. The watcher will start monitoring the vault. Make a change to any file in the vault.
3. After the debounce period (default 5 minutes), a git commit and restic backup will trigger.
4. Check the health endpoint at `http://localhost:8080/health` to verify status.

For Docker, use the Quick Start compose snippet from `README.md` and run `docker exec vault-backup restic init` to initialize the repository on first run.

## Key Files

Point the user to the most important files for understanding the project:

- `src/vault_backup/__main__.py` - Entry point: structured logging, Sentry init, signal handling
- `src/vault_backup/watcher.py` - File system monitoring with watchdog and path-segment ignore patterns
- `src/vault_backup/backup.py` - Git commit, restic backup, LLM commit message generation
- `src/vault_backup/config.py` - Frozen dataclass configuration loaded from environment variables
- `src/vault_backup/health.py` - HTTP `/health` and `/ready` endpoints
- `src/vault_backup/ui.py` - htmx-powered web UI at `/ui` for browsing snapshots and restoring files
- `Dockerfile` - Alpine-based multi-arch container image
- `pyproject.toml` - Project metadata, dependencies, ruff/pytest config

## Common Tasks

- **Run tests:**
  ```bash
  uv run --extra dev pytest -v
  ```
- **Run tests with coverage:**
  ```bash
  uv run --extra dev pytest --cov=vault_backup --cov-report=term-missing
  ```
- **Lint:**
  ```bash
  uv run --extra dev ruff check src/
  uv run --extra dev ruff format src/
  ```
- **Build the container:**
  ```bash
  docker build -t vault-backup .
  ```
- **Check issue tracker (beads):**
  ```bash
  bd ready
  bd list --all
  ```
