"""FCM (Firebase Cloud Messaging) push sender.

Uses Firebase Admin SDK service account to send FCM messages
via the HTTP v1 API.
"""

from __future__ import annotations

import json
import logging
import time
from pathlib import Path

import httpx

from src.config import settings

log = logging.getLogger(__name__)

FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
FCM_BASE = "https://fcm.googleapis.com/v1"


class FCMPusher:
    """Sends push notifications via Firebase Cloud Messaging (FCM) v1 API."""

    def __init__(self):
        self._access_token: str | None = None
        self._token_expiry: float = 0.0
        self._project_id: str | None = None

    def _load_credentials(self) -> dict | None:
        """Decode and return the Firebase service account credentials."""
        raw = settings.fcm_credentials
        if not raw:
            log.warning("FCM_CREDENTIALS not configured")
            return None
        try:
            # Credentials may be base64-encoded or raw JSON
            import base64
            try:
                decoded = base64.b64decode(raw)
                return json.loads(decoded)
            except Exception:
                return json.loads(raw)
        except Exception as e:
            log.warning("Failed to parse FCM_CREDENTIALS: %s", e)
            return None

    def _get_access_token(self) -> str | None:
        """Get a valid OAuth2 access token for Firebase Cloud Messaging."""
        # Return cached token if still valid
        if self._access_token and time.time() < self._token_expiry - 60:
            return self._access_token

        creds = self._load_credentials()
        if not creds:
            return None

        self._project_id = creds.get("project_id", "yolonotifier")

        # Request OAuth2 token
        try:
            with httpx.Client(timeout=15) as client:
                resp = client.post(
                    "https://oauth2.googleapis.com/token",
                    data={
                        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                        "assertion": self._create_jwt(creds),
                    },
                )
                if resp.status_code == 200:
                    data = resp.json()
                    self._access_token = data["access_token"]
                    self._token_expiry = time.time() + data.get("expires_in", 3600)
                    return self._access_token
                else:
                    log.warning("OAuth2 token request failed: %s", resp.text[:200])
                    return None
        except Exception as e:
            log.warning("OAuth2 error: %s", e)
            return None

    def _create_jwt(self, creds: dict) -> str:
        """Create a JWT assertion for OAuth2 client credentials grant.
        
        Uses the service account's private key to sign a JWT.
        """
        import jwt as pyjwt

        now = int(time.time())
        payload = {
            "iss": creds["client_email"],
            "sub": creds["client_email"],
            "aud": "https://oauth2.googleapis.com/token",
            "iat": now,
            "exp": now + 3600,
            "scope": FCM_SCOPE,
        }
        return pyjwt.encode(payload, creds["private_key"], algorithm="RS256")

    def send_push(
        self,
        token: str,
        title: str,
        body: str,
        image_url: str | None = None,
        data: dict | None = None,
    ) -> bool:
        """Send an FCM push notification to a single device.

        Args:
            token: Device FCM registration token.
            title: Notification title.
            body: Notification body text.
            image_url: Optional image URL for the notification.
            data: Optional data payload (sent as key-value pairs).

        Returns:
            True if push was sent successfully.
        """
        access_token = self._get_access_token()
        if not access_token or not self._project_id:
            return False

        # Build FCM v1 message
        message: dict = {
            "token": token,
            "notification": {
                "title": title,
                "body": body,
            },
            "android": {
                "priority": "high",
                "notification": {
                    "channel_id": "codebridge-alerts",
                    "sound": "default",
                },
            },
            "apns": {
                "payload": {
                    "aps": {
                        "sound": "default",
                        "badge": 1,
                        "content-available": 1,
                    }
                }
            },
        }

        if image_url:
            message["android"]["notification"]["image"] = image_url
        if data:
            message["data"] = {str(k): str(v) for k, v in data.items()}

        url = f"{FCM_BASE}/projects/{self._project_id}/messages:send"
        headers = {
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
        }

        try:
            with httpx.Client(timeout=15) as client:
                resp = client.post(url, headers=headers, json={"message": message})
                if resp.status_code == 200:
                    log.info("FCM push sent to %s...: %s", token[:8], title)
                    return True
                else:
                    log.warning("FCM send failed: HTTP %d %s", resp.status_code, resp.text[:200])
                    return False
        except Exception as e:
            log.warning("FCM error: %s", e)
            return False

    def send_to_all_devices(
        self,
        title: str,
        body: str,
        image_url: str | None = None,
        data: dict | None = None,
    ) -> int:
        """Send FCM push to all registered device tokens.

        Returns:
            Number of successful pushes.
        """
        from src.db import get_db

        try:
            db = get_db()
            result = db.table("device_tokens").select("token").execute()
            tokens = [r["token"] for r in (result.data or []) if r.get("token")]
        except Exception as e:
            log.warning("Failed to fetch device tokens: %s", e)
            return 0

        if not tokens:
            log.info("No device tokens registered for FCM")
            return 0

        success = 0
        for token in tokens:
            try:
                if self.send_push(token, title, body, image_url, data):
                    success += 1
            except Exception as e:
                log.warning("FCM push to %s... failed: %s", token[:8], e)

        log.info("FCM: %d/%d pushes sent", success, len(tokens))
        return success
