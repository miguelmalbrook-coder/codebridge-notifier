"""Utils — RTSP URL redaction and helpers."""

from __future__ import annotations

import re


def redact_rtsp_url(url: str) -> str:
    """Strip embedded user:pass from RTSP URLs for logging."""
    return re.sub(r"://[^/@]+@", "://<redacted>@", url)
