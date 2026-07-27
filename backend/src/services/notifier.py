"""Notification dispatcher — sends ntfy (push) + Telegram (debug) alerts."""

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

    async def send_ntfy(self, title: str, body: str, image_url: str | None = None) -> bool:
        """Send push notification via ntfy."""
        payload = {
            "topic": NTFY_TOPIC,
            "title": title,
            "message": body,
            "priority": "high",
            "tags": ["warning", "camera"],
        }
        if image_url:
            payload["attach"] = image_url
            payload["click"] = image_url

        try:
            async with httpx.AsyncClient(timeout=10) as client:
                resp = await client.post(
                    f"{NTFY_URL}/publish",
                    json=payload,
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
    async def send_telegram(self, text: str) -> bool:
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

        async with httpx.AsyncClient(timeout=10) as client:
            try:
                resp = await client.post(url, json=payload)
                if resp.status_code != 200:
                    log.warning("Telegram send failed: %s", resp.text)
                    return False
                return True
            except Exception as e:
                log.warning("Telegram error: %s", e)
                return False

    async def send_telegram_photo(self, photo_path: str | Path, caption: str = "") -> bool:
        """Send a photo with caption to Telegram."""
        if not settings.has_telegram:
            return False

        url = (
            f"https://api.telegram.org/bot{settings.telegram_bot_token}"
            f"/sendPhoto"
        )

        async with httpx.AsyncClient(timeout=30) as client:
            try:
                with open(photo_path, "rb") as f:
                    files = {"photo": f}
                    data = {
                        "chat_id": settings.telegram_chat_id,
                        "caption": caption[:1024],
                    }
                    resp = await client.post(url, data=data, files=files)
                    return resp.status_code == 200
            except Exception as e:
                log.warning("Telegram photo error: %s", e)
                return False
