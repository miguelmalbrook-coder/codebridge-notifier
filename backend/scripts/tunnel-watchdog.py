#!/usr/bin/env python3
"""Watchdog that keeps tunnel URLs in Supabase in sync.

Uses Docker SDK to read cloudflared container logs and extract tunnel URLs.
Auto-updates app_config in Supabase whenever URLs change.
"""

import logging
import os
import re
import time

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

TUNNEL_URL_RE = re.compile(r"https://[a-z0-9-]+\.trycloudflare\.com")

_last_api_url = ""
_last_ntfy_url = ""
_config_id = ""


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


def main():
    global _config_id, _last_api_url, _last_ntfy_url

    if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
        log.error("SUPABASE_URL and SUPABASE_SERVICE_KEY are required")
        return

    _config_id = get_config_id()
    if not _config_id:
        log.error("Could not find or create app_config row in Supabase")
        return

    log.info("Tunnel watchdog started (polling every %ds)", POLL_INTERVAL)

    while True:
        try:
            api_url = get_tunnel_url(API_TUNNEL_NAME)
            ntfy_url = get_tunnel_url(NTFY_TUNNEL_NAME)

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
