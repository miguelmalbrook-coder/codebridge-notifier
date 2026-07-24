"""Pydantic models for API requests/responses."""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


# --- Cameras ---

class CameraOut(BaseModel):
    id: str
    alias: str
    status: Literal["online", "offline", "error"]
    last_seen: datetime | None = None
    created_at: datetime

    class Config:
        from_attributes = True


class CameraUpdate(BaseModel):
    alias: str | None = None
    status: str | None = None


# --- Alerts ---

class AlertOut(BaseModel):
    id: str
    camera_id: str
    camera_alias: str = ""
    class_name: str
    confidence: float
    snapshot_url: str = ""
    seen_at: datetime

    class Config:
        from_attributes = True


class AlertList(BaseModel):
    alerts: list[AlertOut]
    total: int
    page: int
    per_page: int


# --- Health ---

class HealthResponse(BaseModel):
    status: str = "ok"
    cameras: int = 0
    uptime: float = 0.0
    version: str = "0.1.0"


# --- Push ---

class RegisterDeviceRequest(BaseModel):
    token: str
    platform: Literal["android", "ios"] = "android"


class RegisterDeviceResponse(BaseModel):
    success: bool
    message: str = "Device registered"


# --- Config ---

class ConfigResponse(BaseModel):
    tunnel_url: str = ""
    version: str = "0.1.0"
