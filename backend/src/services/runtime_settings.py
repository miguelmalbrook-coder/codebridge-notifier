"""Runtime-configurable settings — can be changed via API without restart."""

from __future__ import annotations

import threading


class RuntimeSettings:
    """Thread-safe runtime settings that the Flutter app can change on the fly."""

    def __init__(self):
        self._lock = threading.Lock()
        self._mode = "yolo"          # "yolo" (pure YOLO) or "motion" (motion + YOLO)
        self._model = "yolo11s.pt"    # YOLO model filename
        self._confidence = 0.40       # YOLO confidence threshold
        self._cooldown = 15           # Same-class cooldown in seconds

    # ── Mode ──────────────────────────────────────────

    @property
    def mode(self) -> str:
        with self._lock:
            return self._mode

    @mode.setter
    def mode(self, value: str):
        value = value.lower()
        if value not in ("yolo", "motion"):
            raise ValueError("Mode must be 'yolo' or 'motion'")
        with self._lock:
            self._mode = value

    # ── Model ─────────────────────────────────────────

    @property
    def model(self) -> str:
        with self._lock:
            return self._model

    @model.setter
    def model(self, value: str):
        if not value.endswith(".pt"):
            raise ValueError("Model must be a .pt file")
        with self._lock:
            self._model = value

    # ── Confidence ────────────────────────────────────

    @property
    def confidence(self) -> float:
        with self._lock:
            return self._confidence

    @confidence.setter
    def confidence(self, value: float):
        value = round(float(value), 2)
        if value < 0.01 or value > 0.99:
            raise ValueError("Confidence must be between 0.01 and 0.99")
        with self._lock:
            self._confidence = value

    # ── Cooldown ──────────────────────────────────────

    @property
    def cooldown(self) -> int:
        with self._lock:
            return self._cooldown

    @cooldown.setter
    def cooldown(self, value: int):
        value = int(value)
        if value < 1 or value > 600:
            raise ValueError("Cooldown must be between 1 and 600 seconds")
        with self._lock:
            self._cooldown = value

    def as_dict(self) -> dict:
        """Return all settings as a JSON-serialisable dict."""
        with self._lock:
            return {
                "mode": self._mode,
                "model": self._model,
                "confidence": self._confidence,
                "cooldown": self._cooldown,
            }


# Global singleton
_settings = RuntimeSettings()


def get_runtime_settings() -> RuntimeSettings:
    return _settings
