"""Notification dispatcher — sends ntfy (push) + Telegram (debug) alerts.
Synchronous methods because the detector runs in a background thread.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from pathlib import Path

import httpx

from src.config import settings
from src.services.runtime_settings import get_runtime_settings

log = logging.getLogger(__name__)

NTFY_URL = "http://127.0.0.1:8090"
NTFY_TOPIC = "codebridge-alerts"


class Notifier:
    """Sends alerts to ntfy (customer push) and Telegram (debug)."""

    def __init__(self):
        pass

    # ── ntfy (Customer push) ──────────────────────────────────────────

    def send_ntfy(self, title: str, body: str, image_url: str | None = None) -> bool:
        """Send push notification via ntfy.

        Publishes directly to the topic endpoint (not /publish) because
        ntfy ignores the 'topic' field in JSON posted to /publish.
        Uses headers for metadata (Title, Priority, Tags).
        """
        headers = {
            "Title": title,
            "Priority": "high",
            "Tags": "warning,camera",
        }
        if image_url:
            headers["Click"] = image_url

        try:
            with httpx.Client(timeout=10) as client:
                resp = client.post(
                    f"{NTFY_URL}/{NTFY_TOPIC}",
                    content=body.encode("utf-8"),
                    headers=headers,
                )
                if resp.status_code == 200:
                    log.info("ntfy sent: %s", title)
                    return True
                else:
                    log.warning("ntfy failed (%d): %s", resp.status_code, resp.text[:200])
                    return False
        except Exception as e:
            log.warning("ntfy error: %s", e)
            return False

    # ── Telegram (Admin debug) ─────────────────────────────────────────
    def send_telegram(self, text: str) -> bool:
        """Send a text message to the configured Telegram chat."""
        if not settings.has_telegram:
            return False

        url = (
            f"https://api.telegram.org/bot{settings.telegram_bot_token}"
            f"/sendMessage"
        )
        payload = {
            "chat_id": settings.telegram_chat_id,
            "text": text[:4096],  # Telegram 4096 char limit
            "parse_mode": "HTML",
        }

        with httpx.Client(timeout=10) as client:
            try:
                resp = client.post(url, json=payload)
                if resp.status_code != 200:
                    log.warning("Telegram send failed: %s", resp.text)
                    return False
                return True
            except Exception as e:
                log.warning("Telegram error: %s", e)
                return False

    def send_telegram_photo(self, photo_path: str | Path, caption: str = "") -> bool:
        """Send a photo with caption to Telegram."""
        if not settings.has_telegram:
            return False

        url = (
            f"https://api.telegram.org/bot{settings.telegram_bot_token}"
            f"/sendPhoto"
        )

        with httpx.Client(timeout=30) as client:
            try:
                with open(photo_path, "rb") as f:
                    files = {"photo": f}
                    data = {
                        "chat_id": settings.telegram_chat_id,
                        "caption": caption[:1024],
                    }
                    resp = client.post(url, data=data, files=files)
                    return resp.status_code == 200
            except Exception as e:
                log.warning("Telegram photo error: %s", e)
                return False
