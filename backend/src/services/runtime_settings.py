"""Runtime-configurable settings — persisted to disk, changeable via API."""

from __future__ import annotations

import json
import logging
import threading
from pathlib import Path

log = logging.getLogger(__name__)

SETTINGS_FILE = Path("/app/data/runtime_settings.json")

# Default safety-net targets (overridden at runtime from YOLO model)
_DEFAULT_TARGETS = ["person", "car", "cat", "dog"]


class RuntimeSettings:
    """Thread-safe runtime settings persisted to disk."""

    def __init__(self):
        self._lock = threading.Lock()
        self._mode = "yolo"
        self._model = "yolo11s.pt"
        self._confidence = 0.40
        self._cooldown = 15
        self._targets = list(_DEFAULT_TARGETS)
        self._available_targets: list[str] = []
        self._load()

    # ── Persistence ───────────────────────────────────

    def _load(self):
        try:
            if SETTINGS_FILE.exists():
                data = json.loads(SETTINGS_FILE.read_text())
                self._mode = data.get("mode", self._mode)
                self._model = data.get("model", self._model)
                self._confidence = data.get("confidence", self._confidence)
                self._cooldown = data.get("cooldown", self._cooldown)
                self._targets = data.get("targets", self._targets)
                log.info("Loaded runtime settings from %s", SETTINGS_FILE)
        except Exception as e:
            log.warning("Failed to load settings, using defaults: %s", e)

    def _save(self):
        try:
            SETTINGS_FILE.parent.mkdir(parents=True, exist_ok=True)
            SETTINGS_FILE.write_text(json.dumps(self._persist_dict(), indent=2))
            log.info("Saved runtime settings to %s", SETTINGS_FILE)
        except Exception as e:
            log.warning("Failed to save settings: %s", e)

    def _persist_dict(self) -> dict:
        """Dict that goes to disk (no available_targets)."""
        return {
            "mode": self._mode,
            "model": self._model,
            "confidence": self._confidence,
            "cooldown": self._cooldown,
            "targets": list(self._targets),
        }

    # ── Available targets (set once from YOLO model) ──

    def set_available_targets(self, names: list[str]):
        with self._lock:
            self._available_targets = list(names)

    # ── Properties ────────────────────────────────────

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
            self._save()

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
            self._save()

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
            self._save()

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
            self._save()

    @property
    def targets(self) -> list[str]:
        with self._lock:
            return list(self._targets)

    @targets.setter
    def targets(self, value: list[str]):
        with self._lock:
            available = set(self._available_targets) if self._available_targets else set(_DEFAULT_TARGETS)
            invalid = [t for t in value if t not in available]
            if invalid:
                raise ValueError(f"Unknown targets: {invalid}")
            self._targets = list(value)
            self._save()

    def as_dict(self) -> dict:
        with self._lock:
            return {
                "mode": self._mode,
                "model": self._model,
                "confidence": self._confidence,
                "cooldown": self._cooldown,
                "targets": list(self._targets),
                "available_targets": list(self._available_targets) if self._available_targets else list(_DEFAULT_TARGETS),
            }


# Global singleton
_settings = RuntimeSettings()


def get_runtime_settings() -> RuntimeSettings:
    return _settings
