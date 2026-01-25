---
name: run-local
description: Run vault-backup locally with test configuration
disable-model-invocation: true
---

# Run Local

Run the vault backup service locally for testing.

## Prerequisites

- Python 3.12+ with the package installed (`pip install -e .`)
- A test vault directory

## Steps

1. Create a test vault if it doesn't exist:
   ```bash
   mkdir -p /tmp/test-vault
   echo "# Test Note" > /tmp/test-vault/test.md
   ```

2. Run in dry-run mode (no actual backups):
   ```bash
   VAULT_PATH=/tmp/test-vault \
   DRY_RUN=true \
   RESTIC_REPOSITORY=local:/tmp/test-backup \
   RESTIC_PASSWORD=test \
   AZURE_ACCOUNT_NAME=dummy \
   AZURE_ACCOUNT_KEY=dummy \
   python -m vault_backup
   ```

3. The health endpoint will be available at http://localhost:8080/health

## Testing Changes

To trigger a backup cycle:
1. Modify a file in `/tmp/test-vault`
2. Wait for debounce period (default 5 min, or set `DEBOUNCE_SECONDS=10` for faster testing)
3. Watch logs for commit and backup activity

## Quick Test Command

For rapid iteration with 10-second debounce:

```bash
VAULT_PATH=/tmp/test-vault \
DRY_RUN=true \
DEBOUNCE_SECONDS=10 \
RESTIC_REPOSITORY=local:/tmp/test-backup \
RESTIC_PASSWORD=test \
AZURE_ACCOUNT_NAME=dummy \
AZURE_ACCOUNT_KEY=dummy \
python -m vault_backup
```
