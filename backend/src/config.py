"""All env vars with validation, no hardcoded values."""

from __future__ import annotations

import base64
import json
import os
from pathlib import Path
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
    )

    # --- Supabase ---
    supabase_url: str = ""
    supabase_service_key: str = ""
    supabase_anon_key: str = ""

    # --- Camera(s) ---
    # Format: "Alias1|rtsp://user:pass@host:554/stream,Alias2|rtsp://..."
    rtsp_urls: str = ""
    detection_targets: str = "person,car,cat,dog"
    confidence_threshold: float = 0.5
    cooldown_seconds: int = 60

    # --- Telegram (optional, debug/admin only) ---
    telegram_bot_token: str = ""
    telegram_chat_id: str = ""

    # --- FCM (optional, customer push) ---
    fcm_credentials: str = ""

    # --- Paths ---
    data_dir: str = str(Path(__file__).parent.parent / "data")
    snapshots_dir: str = str(Path(__file__).parent.parent / "snapshots")

    # --- Runtime ---
    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR"] = "INFO"
    host: str = "0.0.0.0"
    port: int = 8000

    @property
    def camera_list(self) -> list[dict[str, str]]:
        """Parse RTSP_URLS into [{"alias": "FrontDoor", "url": "rtsp://..."}]."""
        if not self.rtsp_urls.strip():
            return []
        cameras = []
        for entry in self.rtsp_urls.split(","):
            entry = entry.strip()
            if "|" in entry:
                alias, url = entry.split("|", 1)
                cameras.append({"alias": alias.strip(), "url": url.strip()})
            else:
                cameras.append({"alias": f"Camera {len(cameras) + 1}", "url": entry})
        return cameras

    @property
    def target_classes(self) -> list[str]:
        return [c.strip().lower() for c in self.detection_targets.split(",") if c.strip()]

    @property
    def fcm_credentials_dict(self) -> dict | None:
        if not self.fcm_credentials:
            return None
        try:
            return json.loads(base64.b64decode(self.fcm_credentials).decode())
        except Exception:
            return None

    @property
    def has_telegram(self) -> bool:
        return bool(self.telegram_bot_token and self.telegram_chat_id)

    @property
    def has_fcm(self) -> bool:
        return bool(self.fcm_credentials)


settings = Settings()
