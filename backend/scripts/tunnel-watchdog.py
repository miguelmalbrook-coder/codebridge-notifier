#!/usr/bin/env python3
"""Watchdog that keeps tunnel URLs in Supabase in sync.

Uses Docker SDK to read cloudflared container logs and extract tunnel URLs.
Auto-updates app_config in Supabase whenever URLs change.
Detects downtime and sends ntfy/FCM notifications when the backend comes
back online after being down for more than 1 hour.
"""

import json
import logging
import os
import re
import time
from datetime import datetime, timezone
from pathlib import Path

import httpx

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger("tunnel-watchdog")

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_KEY", "")
API_TUNNEL_NAME = os.environ.get("API_TUNNEL_NAME", "codebridge-cloudflared-api")
NTFY_TUNNEL_NAME = os.environ.get("NTFY_TUNNEL_NAME", "codebridge-cloudflared-ntfy")
POLL_INTERVAL = int(os.environ.get("POLL_INTERVAL", "15"))
FCM_CREDENTIALS = os.environ.get("FCM_CREDENTIALS", "")

TUNNEL_URL_RE = re.compile(r"https://[a-z0-9-]+\.trycloudflare\.com")

# ntfy endpoint (local, proxied through cloudflared-ntfy tunnel)
NTFY_URL = "http://127.0.0.1:8090"
NTFY_TOPIC = "codebridge-alerts"

# Downtime threshold: 1 hour in seconds
DOWNTIME_THRESHOLD_SECONDS = 3600

# State file for tracking downtime
STATE_FILE = Path("/tmp/watchdog_state.json")

_last_api_url = ""
_last_ntfy_url = ""
_config_id = ""


# ── State persistence ───────────────────────────────────────────────────────


def load_state() -> dict:
    """Load watchdog state from disk."""
    try:
        if STATE_FILE.exists():
            return json.loads(STATE_FILE.read_text())
    except Exception as e:
        log.warning("Failed to load state: %s", e)
    return {}


def save_state(state: dict) -> None:
    """Persist watchdog state to disk."""
    try:
        STATE_FILE.write_text(json.dumps(state))
    except Exception as e:
        log.warning("Failed to save state: %s", e)


def now_iso() -> str:
    """Current UTC time as ISO string."""
    return datetime.now(timezone.utc).isoformat()


def parse_iso(s: str) -> datetime | None:
    """Parse an ISO timestamp string."""
    try:
        return datetime.fromisoformat(s)
    except Exception:
        return None


def format_duration(seconds: float) -> str:
    """Format seconds into a human-readable duration like '2 hours 15 minutes'."""
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    if hours > 0 and minutes > 0:
        return f"{hours} hours {minutes} minutes"
    elif hours > 0:
        return f"{hours} hours"
    elif minutes > 0:
        return f"{minutes} minutes"
    else:
        return "less than a minute"


def format_time_hhmm(iso_str: str) -> str:
    """Format an ISO timestamp to HH:MM (24h, local time)."""
    dt = parse_iso(iso_str)
    if dt is None:
        return "??:??"
    return dt.strftime("%H:%M")


# ── Notification: ntfy ──────────────────────────────────────────────────────


def send_ntfy(title: str, body: str) -> bool:
    """Send a notification via ntfy."""
    headers = {
        "Title": title,
        "Priority": "default",
        "Tags": "warning,surveillance",
    }
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


# ── Notification: FCM ───────────────────────────────────────────────────────


class FCMPusher:
    """Standalone FCM push sender using Firebase HTTP v1 API."""

    FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
    FCM_BASE = "https://fcm.googleapis.com/v1"

    def __init__(self, credentials_b64: str):
        self._credentials_b64 = credentials_b64
        self._access_token: str | None = None
        self._token_expiry: float = 0.0
        self._project_id: str | None = None

    def _load_credentials(self) -> dict | None:
        import base64
        raw = self._credentials_b64
        if not raw:
            return None
        try:
            try:
                decoded = base64.b64decode(raw)
                return json.loads(decoded)
            except Exception:
                return json.loads(raw)
        except Exception as e:
            log.warning("Failed to parse FCM credentials: %s", e)
            return None

    def _create_jwt(self, creds: dict) -> str:
        import jwt as pyjwt
        now = int(time.time())
        payload = {
            "iss": creds["client_email"],
            "sub": creds["client_email"],
            "aud": "https://oauth2.googleapis.com/token",
            "iat": now,
            "exp": now + 3600,
            "scope": self.FCM_SCOPE,
        }
        return pyjwt.encode(payload, creds["private_key"], algorithm="RS256")

    def _get_access_token(self) -> str | None:
        if self._access_token and time.time() < self._token_expiry - 60:
            return self._access_token
        creds = self._load_credentials()
        if not creds:
            return None
        self._project_id = creds.get("project_id")
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
                    log.warning("FCM OAuth2 token failed: %s", resp.text[:200])
                    return None
        except Exception as e:
            log.warning("FCM OAuth2 error: %s", e)
            return None

    def send_push(self, token: str, title: str, body: str) -> bool:
        access_token = self._get_access_token()
        if not access_token or not self._project_id:
            return False
        message = {
            "token": token,
            "notification": {"title": title, "body": body},
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
        url = f"{self.FCM_BASE}/projects/{self._project_id}/messages:send"
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


def get_fcm_pusher() -> FCMPusher | None:
    """Create an FCM pusher if credentials are available."""
    if not FCM_CREDENTIALS:
        return None
    try:
        import jwt as _pyjwt  # noqa: F401 — verify pyjwt is importable
        return FCMPusher(FCM_CREDENTIALS)
    except ImportError:
        log.debug("pyjwt not installed — FCM push disabled")
        return None


def send_fcm_pushes(title: str, body: str) -> int:
    """Send FCM push to all registered device tokens. Returns count of successes."""
    pusher = get_fcm_pusher()
    if not pusher:
        return 0
    # Fetch tokens from Supabase
    headers = {
        "apikey": SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_KEY}",
    }
    try:
        r = httpx.get(
            f"{SUPABASE_URL}/rest/v1/device_tokens?select=token",
            headers=headers, timeout=15,
        )
        if r.status_code != 200 or not r.json():
            return 0
        tokens = [row["token"] for row in r.json() if row.get("token")]
    except Exception as e:
        log.warning("Failed to fetch device tokens: %s", e)
        return 0

    success = 0
    for token in tokens:
        try:
            if pusher.send_push(token, title, body):
                success += 1
        except Exception as e:
            log.warning("FCM push to %s... failed: %s", token[:8], e)
    if tokens:
        log.info("FCM: %d/%d pushes sent", success, len(tokens))
    return success


# ── Supabase ────────────────────────────────────────────────────────────────


def get_tunnel_url(container_name: str) -> str:
    """Read cloudflared container logs and extract tunnel URL."""
    try:
        import docker
        client = docker.from_env()
        container = client.containers.get(container_name)
        logs = container.logs(tail=50).decode("utf-8", errors="replace")
        match = TUNNEL_URL_RE.search(logs)
        if match:
            return match.group(0)
    except Exception as e:
        log.warning("Failed to read %s logs: %s", container_name, e)
    return ""


def update_supabase(api_url: str, ntfy_url: str) -> bool:
    """Update app_config in Supabase with current tunnel URLs."""
    headers = {
        "apikey": SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }
    try:
        r = httpx.patch(
            f"{SUPABASE_URL}/rest/v1/app_config?id=eq.{_config_id}",
            json={"tunnel_url": api_url, "ntfy_tunnel_url": ntfy_url},
            headers=headers, timeout=15,
        )
        if r.status_code in (200, 204):
            log.info("Supabase updated: API=%s  ntfy=%s", api_url, ntfy_url)
            return True
        else:
            log.warning("Supabase update failed: HTTP %d %s", r.status_code, r.text[:100])
            return False
    except Exception as e:
        log.warning("Supabase error: %s", e)
        return False


def get_config_id() -> str:
    """Get or create the first row's ID from app_config."""
    headers = {
        "apikey": SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_KEY}",
    }
    try:
        r = httpx.get(
            f"{SUPABASE_URL}/rest/v1/app_config?select=id&limit=1",
            headers=headers, timeout=15,
        )
        if r.status_code == 200 and r.json():
            return r.json()[0]["id"]
    except Exception as e:
        log.warning("Failed to get config ID: %s", e)

    # Try to create it
    try:
        headers["Content-Type"] = "application/json"
        headers["Prefer"] = "return=representation"
        r = httpx.post(
            f"{SUPABASE_URL}/rest/v1/app_config",
            json={"tunnel_url": "", "ntfy_tunnel_url": "", "subscribed": True},
            headers=headers, timeout=15,
        )
        if r.status_code == 201 and r.json():
            log.info("Created app_config row")
            return r.json()[0]["id"]
    except Exception as e:
        log.warning("Failed to create app_config: %s", e)
    return ""


# ── Downtime detection ─────────────────────────────────────────────────────


def check_downtime_and_notify(api_url: str, state: dict) -> dict:
    """Check if the API tunnel came back after downtime.

    Tracks when the URL becomes empty (downtime starts) and when it
    returns (downtime ends). If downtime exceeded the threshold,
    sends ntfy + FCM notifications.

    Returns the updated state dict.
    """
    url_is_empty = not api_url or not api_url.strip()
    now = now_iso()
    down_since = state.get("down_since")

    if url_is_empty:
        # URL is unavailable — record downtime start if not already tracked
        if not down_since:
            state["down_since"] = now
            log.info("Tunnel URL unavailable — downtime tracking started at %s", now)
    else:
        # URL is available — check if we were tracking downtime
        if down_since:
            down_start = parse_iso(down_since)
            if down_start:
                downtime_seconds = (datetime.now(timezone.utc) - down_start).total_seconds()
                downtime_str = format_duration(downtime_seconds)
                start_hhmm = format_time_hhmm(down_since)
                end_hhmm = format_time_hhmm(now)

                log.info(
                    "Tunnel URL recovered after %s of downtime (from %s to %s)",
                    downtime_str, start_hhmm, end_hhmm,
                )

                if downtime_seconds >= DOWNTIME_THRESHOLD_SECONDS:
                    # Send notification
                    body = (
                        f"AI surveillance was not active for the past {downtime_str} "
                        f"between {start_hhmm} and {end_hhmm}, "
                        f"likely because your network or cameras were unavailable."
                    )
                    log.warning("Downtime exceeded threshold — sending alert")
                    send_ntfy("⚠️ Surveillance Downtime", body)
                    send_fcm_pushes("⚠️ Surveillance Downtime", body)

            # Clear downtime tracking
            state.pop("down_since", None)

    state["last_url_check"] = now
    return state


# ── Main ────────────────────────────────────────────────────────────────────


def main():
    global _config_id, _last_api_url, _last_ntfy_url

    # Validate required env vars
    if not SUPABASE_URL:
        log.error("SUPABASE_URL is required but not set")
        return
    if not SUPABASE_SERVICE_KEY:
        log.error("SUPABASE_SERVICE_KEY is required but not set")
        return

    _config_id = get_config_id()
    if not _config_id:
        log.error("Could not find or create app_config row in Supabase")
        return

    log.info("Tunnel watchdog started (polling every %ds)", POLL_INTERVAL)
    if FCM_CREDENTIALS:
        log.info("FCM push notifications enabled")
    else:
        log.info("FCM push notifications disabled (FCM_CREDENTIALS not set)")

    state = load_state()

    while True:
        try:
            api_url = get_tunnel_url(API_TUNNEL_NAME)
            ntfy_url = get_tunnel_url(NTFY_TUNNEL_NAME)

            # ── Downtime detection (API tunnel) ──
            state = check_downtime_and_notify(api_url, state)
            save_state(state)

            # ── Update Supabase on URL change ──
            changed = False
            if api_url and api_url != _last_api_url:
                log.info("API tunnel URL: %s", api_url)
                _last_api_url = api_url
                changed = True

            if ntfy_url and ntfy_url != _last_ntfy_url:
                log.info("ntfy tunnel URL: %s", ntfy_url)
                _last_ntfy_url = ntfy_url
                changed = True

            if changed:
                update_supabase(_last_api_url, _last_ntfy_url)
        except Exception as e:
            log.warning("Watchdog error: %s", e)

        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    main()
