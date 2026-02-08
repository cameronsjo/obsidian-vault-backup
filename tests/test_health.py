"""Tests for vault_backup.health."""

from __future__ import annotations

import json
import time
from http.server import HTTPServer
from pathlib import Path
from threading import Thread
from unittest.mock import MagicMock, patch

import pytest

from vault_backup.config import Config
from vault_backup.health import HealthHandler, HealthServer, HealthState, _health_state


class TestHealthState:
    def test_to_dict_no_state_files(self, default_config: Config, tmp_state_dir: Path) -> None:
        state = HealthState(config=default_config)
        result = state.to_dict()
        assert result["status"] == "healthy"
        assert result["last_commit"] is None
        assert result["last_backup"] is None
        assert result["last_change"] is None
        assert result["pending_changes"] is False
        assert result["commits_since_backup"] == 0
        assert result["sync_state"] is None
        assert "uptime_seconds" in result

    def test_to_dict_with_state_files(self, default_config: Config, tmp_state_dir: Path) -> None:
        now = time.time()
        (tmp_state_dir / "last_commit").write_text(str(now))
        (tmp_state_dir / "last_backup").write_text(str(now))
        (tmp_state_dir / "last_change").write_text(str(now - 100))
        (tmp_state_dir / "pending_changes").write_text("true")

        state = HealthState(config=default_config)
        result = state.to_dict()
        assert result["last_commit"] is not None
        assert result["last_backup"] is not None
        assert result["pending_changes"] is True

    def test_unhealthy_when_stale_backup(self, default_config: Config, tmp_state_dir: Path) -> None:
        now = time.time()
        old_backup = now - 100_000  # >24h ago
        (tmp_state_dir / "last_backup").write_text(str(old_backup))
        (tmp_state_dir / "last_change").write_text(str(now))  # Recent change

        state = HealthState(config=default_config)
        result = state.to_dict()
        assert result["status"] == "unhealthy"

    def test_healthy_when_stale_backup_but_no_changes(
        self, default_config: Config, tmp_state_dir: Path
    ) -> None:
        old_backup = time.time() - 100_000
        (tmp_state_dir / "last_backup").write_text(str(old_backup))
        # No last_change file -> no changes since backup

        state = HealthState(config=default_config)
        result = state.to_dict()
        assert result["status"] == "healthy"


class TestHealthStateHelpers:
    def test_read_timestamp_valid(self, tmp_path: Path) -> None:
        f = tmp_path / "ts"
        f.write_text("1700000000.5\n")
        assert HealthState._read_timestamp(f) == 1700000000.5

    def test_read_timestamp_missing(self, tmp_path: Path) -> None:
        assert HealthState._read_timestamp(tmp_path / "nope") is None

    def test_read_timestamp_invalid(self, tmp_path: Path) -> None:
        f = tmp_path / "ts"
        f.write_text("not-a-number")
        assert HealthState._read_timestamp(f) is None

    def test_read_bool_true(self, tmp_path: Path) -> None:
        for val in ("true", "1", "yes", "TRUE", "Yes"):
            f = tmp_path / "flag"
            f.write_text(val)
            assert HealthState._read_bool(f) is True

    def test_read_bool_false(self, tmp_path: Path) -> None:
        f = tmp_path / "flag"
        f.write_text("false")
        assert HealthState._read_bool(f) is False

    def test_read_bool_missing(self, tmp_path: Path) -> None:
        assert HealthState._read_bool(tmp_path / "nope") is False

    def test_timestamp_to_iso(self) -> None:
        result = HealthState._timestamp_to_iso(1700000000.0)
        assert result is not None
        assert result.endswith("Z")
        assert "2023-11-14" in result

    def test_timestamp_to_iso_none(self) -> None:
        assert HealthState._timestamp_to_iso(None) is None

    def test_timestamp_to_iso_zero(self) -> None:
        assert HealthState._timestamp_to_iso(0) is None

    def test_read_sync_state_exists(self, tmp_vault: Path) -> None:
        obsidian_dir = tmp_vault / ".obsidian"
        obsidian_dir.mkdir()
        (obsidian_dir / "sync.json").write_text('{"status": "synced"}')
        result = HealthState._read_sync_state(tmp_vault)
        assert result == {"status": "synced"}

    def test_read_sync_state_missing(self, tmp_vault: Path) -> None:
        assert HealthState._read_sync_state(tmp_vault) is None

    def test_read_sync_state_malformed(self, tmp_vault: Path) -> None:
        obsidian_dir = tmp_vault / ".obsidian"
        obsidian_dir.mkdir()
        (obsidian_dir / "sync.json").write_text("not json{{{")
        assert HealthState._read_sync_state(tmp_vault) is None

    def test_count_commits_since_subprocess_failure(self, tmp_path: Path) -> None:
        # Non-git directory should return 0
        result = HealthState._count_commits_since(tmp_path, time.time() - 3600)
        assert result == 0


class TestHealthHandler:
    @pytest.fixture()
    def health_server(self, default_config: Config):
        """Start a real health server for testing."""
        import vault_backup.health as health_mod

        health_mod._health_state = HealthState(config=default_config)
        server = HTTPServer(("127.0.0.1", 0), HealthHandler)
        port = server.server_address[1]
        thread = Thread(target=server.serve_forever, daemon=True)
        thread.start()
        yield f"http://127.0.0.1:{port}"
        server.shutdown()
        health_mod._health_state = None

    def test_health_endpoint(self, health_server: str) -> None:
        import urllib.request

        resp = urllib.request.urlopen(f"{health_server}/health")
        assert resp.status == 200
        body = json.loads(resp.read())
        assert body["status"] == "healthy"
        assert "uptime_seconds" in body

    def test_health_endpoint_trailing_slash(self, health_server: str) -> None:
        import urllib.request

        resp = urllib.request.urlopen(f"{health_server}/health/")
        assert resp.status == 200

    def test_ready_endpoint(self, health_server: str) -> None:
        import urllib.request

        resp = urllib.request.urlopen(f"{health_server}/ready")
        assert resp.status == 200
        body = json.loads(resp.read())
        assert body["ready"] is True

    def test_ready_503_when_not_initialized(self) -> None:
        import urllib.error
        import urllib.request
        import vault_backup.health as health_mod

        health_mod._health_state = None
        server = HTTPServer(("127.0.0.1", 0), HealthHandler)
        port = server.server_address[1]
        thread = Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with pytest.raises(urllib.error.HTTPError) as exc_info:
                urllib.request.urlopen(f"http://127.0.0.1:{port}/ready")
            assert exc_info.value.code == 503
        finally:
            server.shutdown()

    def test_not_found(self, health_server: str) -> None:
        import urllib.error
        import urllib.request

        with pytest.raises(urllib.error.HTTPError) as exc_info:
            urllib.request.urlopen(f"{health_server}/nonexistent")
        assert exc_info.value.code == 404

    def test_500_when_state_not_initialized(self) -> None:
        import urllib.error
        import urllib.request
        import vault_backup.health as health_mod

        health_mod._health_state = None
        server = HTTPServer(("127.0.0.1", 0), HealthHandler)
        port = server.server_address[1]
        thread = Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with pytest.raises(urllib.error.HTTPError) as exc_info:
                urllib.request.urlopen(f"http://127.0.0.1:{port}/health")
            assert exc_info.value.code == 500
        finally:
            server.shutdown()


class TestHealthServer:
    def test_start_and_stop(self, default_config: Config) -> None:
        hs = HealthServer(config=default_config)
        hs.start()
        assert hs.server is not None
        assert hs.thread is not None
        assert hs.thread.is_alive()
        hs.stop()
