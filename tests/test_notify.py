"""Tests for vault_backup.notify."""

from __future__ import annotations

import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from threading import Thread
from typing import Any
from unittest.mock import patch

import pytest

from vault_backup.config import NotifyConfig, NotifyLevel
from vault_backup.notify import (
    DiscordWebhook,
    GenericWebhook,
    Notifier,
    SlackWebhook,
    _post_json,
)


class RecordingHandler(BaseHTTPRequestHandler):
    """Test HTTP handler that records requests."""

    requests: list[dict[str, Any]] = []

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length)) if length else {}
        RecordingHandler.requests.append(
            {
                "path": self.path,
                "body": body,
                "headers": dict(self.headers),
            }
        )
        self.send_response(204)
        self.end_headers()

    def log_message(self, *args: Any) -> None:
        pass


@pytest.fixture()
def webhook_server():
    """Start a local HTTP server that records webhook requests."""
    RecordingHandler.requests = []
    server = HTTPServer(("127.0.0.1", 0), RecordingHandler)
    port = server.server_address[1]
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    yield f"http://127.0.0.1:{port}"
    server.shutdown()


class TestPostJson:
    def test_sends_json_with_user_agent(self, webhook_server: str) -> None:
        result = _post_json(webhook_server, {"test": True})
        assert result is True
        assert len(RecordingHandler.requests) == 1
        req = RecordingHandler.requests[0]
        assert req["body"] == {"test": True}
        assert "ObsidianBackup/" in req["headers"]["User-Agent"]
        assert req["headers"]["Content-Type"] == "application/json"

    def test_returns_true_for_2xx(self, webhook_server: str) -> None:
        assert _post_json(webhook_server, {}) is True

    def test_raises_on_connection_error(self) -> None:
        with pytest.raises(Exception):
            _post_json("http://127.0.0.1:1", {})


class TestDiscordWebhook:
    def test_success_payload(self, webhook_server: str) -> None:
        webhook = DiscordWebhook(webhook_server)
        result = webhook.send("Test Title", "Test message")
        assert result is True
        req = RecordingHandler.requests[0]
        embed = req["body"]["embeds"][0]
        assert embed["title"] == "Test Title"
        assert embed["description"] == "Test message"
        assert embed["color"] == DiscordWebhook.COLOR_SUCCESS

    def test_error_payload_uses_red(self, webhook_server: str) -> None:
        webhook = DiscordWebhook(webhook_server)
        webhook.send("Error", "bad", is_error=True)
        embed = RecordingHandler.requests[0]["body"]["embeds"][0]
        assert embed["color"] == DiscordWebhook.COLOR_ERROR

    def test_username_and_avatar(self, webhook_server: str) -> None:
        webhook = DiscordWebhook(
            webhook_server, username="Backup Bot", avatar_url="https://example.com/bot.png"
        )
        webhook.send("Test", "msg")
        body = RecordingHandler.requests[0]["body"]
        assert body["username"] == "Backup Bot"
        assert body["avatar_url"] == "https://example.com/bot.png"

    def test_no_username_or_avatar_by_default(self, webhook_server: str) -> None:
        webhook = DiscordWebhook(webhook_server)
        webhook.send("Test", "msg")
        body = RecordingHandler.requests[0]["body"]
        assert "username" not in body
        assert "avatar_url" not in body

    def test_connection_failure_returns_false(self) -> None:
        webhook = DiscordWebhook("http://127.0.0.1:1/nope")
        assert webhook.send("Test", "msg") is False


class TestSlackWebhook:
    def test_success_payload(self, webhook_server: str) -> None:
        webhook = SlackWebhook(webhook_server)
        webhook.send("Test", "message")
        body = RecordingHandler.requests[0]["body"]
        assert body["blocks"][0]["text"]["text"].startswith(":white_check_mark:")

    def test_error_payload(self, webhook_server: str) -> None:
        webhook = SlackWebhook(webhook_server)
        webhook.send("Fail", "bad", is_error=True)
        body = RecordingHandler.requests[0]["body"]
        assert body["blocks"][0]["text"]["text"].startswith(":x:")


class TestGenericWebhook:
    def test_success_payload(self, webhook_server: str) -> None:
        webhook = GenericWebhook(webhook_server)
        webhook.send("Test", "message")
        body = RecordingHandler.requests[0]["body"]
        assert body["title"] == "Test"
        assert body["message"] == "message"
        assert body["status"] == "success"
        assert "timestamp" in body

    def test_error_payload(self, webhook_server: str) -> None:
        webhook = GenericWebhook(webhook_server)
        webhook.send("Fail", "bad", is_error=True)
        body = RecordingHandler.requests[0]["body"]
        assert body["status"] == "error"


class TestNotifier:
    def test_no_providers_is_noop(self) -> None:
        config = NotifyConfig()
        notifier = Notifier(config)
        assert len(notifier.providers) == 0
        notifier.send("Test", "msg")  # Should not raise

    def test_creates_providers_from_config(self, webhook_server: str) -> None:
        config = NotifyConfig(
            discord_webhook_url=webhook_server,
            slack_webhook_url=webhook_server + "/slack",
            generic_webhook_url=webhook_server + "/generic",
        )
        notifier = Notifier(config)
        assert len(notifier.providers) == 3

    def test_level_none_suppresses_all(self, webhook_server: str) -> None:
        config = NotifyConfig(
            level=NotifyLevel.NONE,
            discord_webhook_url=webhook_server,
        )
        notifier = Notifier(config)
        notifier.send("Test", "msg")
        notifier.send("Test", "msg", is_error=True)
        assert len(RecordingHandler.requests) == 0

    def test_level_errors_only(self, webhook_server: str) -> None:
        config = NotifyConfig(
            level=NotifyLevel.ERRORS_ONLY,
            discord_webhook_url=webhook_server,
        )
        notifier = Notifier(config)
        notifier.success("Success", "msg")
        assert len(RecordingHandler.requests) == 0
        notifier.error("Error", "msg")
        assert len(RecordingHandler.requests) == 1

    def test_level_success_only(self, webhook_server: str) -> None:
        config = NotifyConfig(
            level=NotifyLevel.SUCCESS_ONLY,
            discord_webhook_url=webhook_server,
        )
        notifier = Notifier(config)
        notifier.error("Error", "msg")
        assert len(RecordingHandler.requests) == 0
        notifier.success("Success", "msg")
        assert len(RecordingHandler.requests) == 1

    def test_level_all_sends_both(self, webhook_server: str) -> None:
        config = NotifyConfig(
            level=NotifyLevel.ALL,
            discord_webhook_url=webhook_server,
        )
        notifier = Notifier(config)
        notifier.success("Success", "msg")
        notifier.error("Error", "msg")
        assert len(RecordingHandler.requests) == 2
