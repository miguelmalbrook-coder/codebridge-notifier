"""Notification dispatcher — sends FCM (customer) + Telegram (debug) alerts."""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from pathlib import Path

import httpx

from src.config import settings

log = logging.getLogger(__name__)


class Notifier:
    """Sends alerts to FCM (push) and Telegram (debug).

    FCM is for customer-facing push notifications.
    Telegram is for admin debugging / system health.
    """

    def __init__(self):
        self._fcm_initialized = False
        self._fcm_app = None
        self._init_fcm()

    def _init_fcm(self):
        """Lazy-init Firebase Admin SDK if credentials provided."""
        creds = settings.fcm_credentials_dict
        if creds:
            try:
                import firebase_admin
                from firebase_admin import credentials

                cred = credentials.Certificate(creds)
                self._fcm_app = firebase_admin.initialize_app(cred)
                self._fcm_initialized = True
                log.info("FCM initialized")
            except Exception as e:
                log.warning("FCM init failed (push will be unavailable): %s", e)

    # ── FCM (Customer push) ────────────────────────────────────────────

    def send_customer_push(self, title: str, body: str, user_id: str | None = None):
        """Send push notification to all registered devices (or a specific user)."""
        if not self._fcm_initialized:
            log.debug("FCM not configured, skipping push: %s", title)
            return False

        from firebase_admin import messaging

        # Build condition or token list
        if user_id:
            condition = f"'user_id' in topics && topic in topics"
            message = messaging.Message(
                notification=messaging.Notification(title=title, body=body),
                topic=f"user_{user_id}",
            )
        else:
            message = messaging.Message(
                notification=messaging.Notification(title=title, body=body),
                topic="all_devices",
            )

        try:
            response = messaging.send(message)
            log.info("FCM sent: %s", response)
            return True
        except Exception as e:
            log.warning("FCM send failed: %s", e)
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
