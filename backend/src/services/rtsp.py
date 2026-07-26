"""RTSP / Snapshot stream reader — yields frames as numpy arrays.

Uses the Hikvision ISAPI HTTP snapshot API (more reliable than RTSP decoding
for Hikvision cameras on slow networks). Falls back to RTSP if needed.
"""

from __future__ import annotations

import logging
import re
import time
from typing import Generator
from urllib.parse import urlparse

import cv2
import numpy as np

log = logging.getLogger(__name__)


def _parse_rtsp_url(rtsp_url: str) -> dict:
    """Extract host, credentials, and channel number from an RTSP URL.

    Returns dict with host, username, password, channel, snapshot_url.
    """
    parsed = urlparse(rtsp_url)
    host = parsed.hostname or "192.168.100.45"
    username = parsed.username or "admin"
    password = parsed.password or ""
    port = parsed.port or 554

    # Extract channel number from path like /Streaming/Channels/102 → 102
    m = re.search(r"/Channels/(\d+)", parsed.path)
    channel = m.group(1) if m else "101"

    snapshot_url = f"http://{host}/ISAPI/Streaming/channels/{channel}/picture"

    return {
        "host": host,
        "username": username,
        "password": password,
        "port": port,
        "channel": channel,
        "snapshot_url": snapshot_url,
        "redacted": re.sub(r"://[^/@]+@", "://<redacted>@", rtsp_url),
    }


class SnapshotReader:
    """Fetches frames via Hikvision ISAPI HTTP snapshot API.

    Uses curl with Digest auth (same as traffic-camera-phase1).
    """

    def __init__(self, rtsp_url: str, interval: float = 0.5):
        self.rtsp_url = rtsp_url
        self.interval = interval
        self._info = _parse_rtsp_url(rtsp_url)
        self._retries = 0
        self._max_retries = 10

    def open(self) -> bool:
        """Verify the snapshot endpoint is reachable."""
        try:
            result = self._fetch()
            if result is not None:
                self._retries = 0
                log.info("Snapshot endpoint OK: %s", self._info["redacted"])
                return True
            return False
        except Exception as e:
            log.warning("Snapshot unreachable: %s — %s", self._info["redacted"], e)
            return False

    def read_frame(self) -> np.ndarray | None:
        """Fetch one frame as a numpy array (BGR). Returns None on failure."""
        try:
            return self._fetch()
        except Exception as e:
            self._retries += 1
            if self._retries > self._max_retries:
                log.error("Too many snapshot failures: %s", self._info["redacted"])
                return None
            log.warning("Snapshot error: %s", e)
            time.sleep(1)
            return None

    def _fetch(self) -> np.ndarray | None:
        """Execute curl to fetch a JPEG frame. Returns decoded BGR frame or None."""
        import subprocess

        creds = f"{self._info['username']}:{self._info['password']}"
        url = f"{self._info['snapshot_url']}?t={int(time.time() * 1000)}"
        cmd = [
            "curl", "-s", "-w", "\n%{http_code}", "--digest", "--user", creds,
            "--connect-timeout", "5", "--max-time", "10",
            "-H", "Cache-Control: no-cache",
            "-H", "Pragma: no-cache",
            url,
        ]
        try:
            result = subprocess.run(cmd, capture_output=True, timeout=15)
            if result.returncode != 0 or not result.stdout:
                self._retries += 1
                return None
            raw = result.stdout
            parts = raw.rsplit(b"\n", 1)
            http_code = parts[-1].decode().strip()
            jpeg_data = parts[0]
            if http_code != "200":
                log.warning("Snapshot HTTP %s (%d bytes)", http_code, len(jpeg_data))
                return None
            buf = np.frombuffer(jpeg_data, dtype=np.uint8)
            frame = cv2.imdecode(buf, cv2.IMREAD_COLOR)
            if frame is None:
                log.warning("Snapshot decode failed (%d bytes)", len(jpeg_data))
                return None
            return frame
        except subprocess.TimeoutExpired:
            log.warning("Snapshot timeout: %s", self._info["redacted"])
            return None
        except Exception as e:
            log.warning("Snapshot exception: %s", e)
            return None

    def release(self):
        pass  # No persistent connection to release

    def redacted_url(self) -> str:
        return self._info["redacted"]


# Keep the RTSPReader class for non-Hikvision cameras
class RTSPReader:
    """Opens an RTSP stream and yields frames via OpenCV."""

    def __init__(self, rtsp_url: str, max_retries: int = 5, retry_delay: float = 3.0):
        self.rtsp_url = rtsp_url
        self.max_retries = max_retries
        self.retry_delay = retry_delay
        self._cap: cv2.VideoCapture | None = None
        self._reconnect_attempts = 0

    def open(self) -> bool:
        self._cap = cv2.VideoCapture(self.rtsp_url, cv2.CAP_FFMPEG)
        self._cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        self._cap.set(cv2.CAP_PROP_FPS, 5)
        opened = self._cap.isOpened()
        if opened:
            self._reconnect_attempts = 0
            log.info("RTSP opened: %s", self._redacted_url())
        else:
            log.warning("Failed to open RTSP: %s", self._redacted_url())
        return opened

    def frames(self) -> Generator[np.ndarray, None, None]:
        while self._reconnect_attempts < self.max_retries:
            if self._cap is None or not self._cap.isOpened():
                if not self.open():
                    self._reconnect_attempts += 1
                    time.sleep(self.retry_delay)
                    continue
            ret, frame = self._cap.read()
            if not ret:
                self._cap.release()
                self._cap = None
                self._reconnect_attempts += 1
                time.sleep(self.retry_delay)
                continue
            self._reconnect_attempts = 0
            yield frame
        log.error("Max retries for %s", self._redacted_url())

    def release(self):
        if self._cap:
            self._cap.release()
            self._cap = None

    def _redacted_url(self) -> str:
        return re.sub(r"://[^/@]+@", "://<redacted>@", self.rtsp_url)


def create_reader(rtsp_url: str) -> RTSPReader | SnapshotReader:
    """Create the best reader for the given URL.

    Hikvision cameras (detected by RTSP URL pattern) use SnapshotReader
    for reliability. Everything else uses standard RTSP.
    """
    if "Streaming/Channels" in rtsp_url:
        return SnapshotReader(rtsp_url)
    return RTSPReader(rtsp_url)
