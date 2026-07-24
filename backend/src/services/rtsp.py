"""RTSP stream reader — yields frames as numpy arrays."""

from __future__ import annotations

import logging
from typing import Generator

import cv2
import numpy as np

log = logging.getLogger(__name__)


class RTSPReader:
    """Opens an RTSP stream and yields frames.

    Usage:
        reader = RTSPReader("rtsp://user:pass@host:554/stream")
        for frame in reader.frames():
            # do something with frame (numpy array)
    """

    def __init__(self, rtsp_url: str, max_retries: int = 5, retry_delay: float = 3.0):
        self.rtsp_url = rtsp_url
        self.max_retries = max_retries
        self.retry_delay = retry_delay
        self._cap: cv2.VideoCapture | None = None
        self._reconnect_attempts = 0

    def open(self) -> bool:
        """Open RTSP stream. Returns True on success."""
        self._cap = cv2.VideoCapture(self.rtsp_url, cv2.CAP_FFMPEG)
        self._cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)  # Minimize latency
        self._cap.set(cv2.CAP_PROP_FPS, 5)  # Lower FPS for detection
        opened = self._cap.isOpened()
        if opened:
            self._reconnect_attempts = 0
            log.info("RTSP stream opened: %s", self._redacted_url())
        else:
            log.warning("Failed to open RTSP: %s", self._redacted_url())
        return opened

    def frames(self) -> Generator[np.ndarray, None, None]:
        """Generator that yields frames (HWC BGR uint8).

        Auto-reconnects on connection loss up to max_retries.
        """
        while self._reconnect_attempts < self.max_retries:
            if self._cap is None or not self._cap.isOpened():
                if not self.open():
                    self._reconnect_attempts += 1
                    import time
                    time.sleep(self.retry_delay)
                    continue

            ret, frame = self._cap.read()
            if not ret:
                log.warning("Frame read failed, reconnecting...")
                self._cap.release()
                self._cap = None
                self._reconnect_attempts += 1
                import time
                time.sleep(self.retry_delay)
                continue

            self._reconnect_attempts = 0  # Reset on success
            yield frame

        log.error("Max retries reached for %s", self._redacted_url())

    def release(self):
        if self._cap:
            self._cap.release()
            self._cap = None

    def _redacted_url(self) -> str:
        import re
        return re.sub(r"://[^/@]+@", "://<redacted>@", self.rtsp_url)
