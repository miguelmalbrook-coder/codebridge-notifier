"""AR YOLO Detector — separate singleton service for on-demand detection.

Independent from the main DetectorService. Has its own model cache, loading
state tracking, and extended class support for AR overlays.

Usage:
    ar = ARDetector.get_instance()
    ar.load_model('yolo11n.pt')
    result = ar.detect(frame, targets=['person', 'cat'])
    # result = {'image': bytes, 'detections': [...]}

Or load asynchronously with a progress callback:
    def on_status(status):
        print(f"AR model: {status}")
    ar.load_model('yolo11s.pt', on_status=on_status)
"""

from __future__ import annotations

import base64
import logging
import threading
import time
from pathlib import Path
from typing import Any, Callable

import cv2
import numpy as np
from ultralytics import YOLO

log = logging.getLogger(__name__)

# Default model for AR detection
AR_DEFAULT_MODEL = "yolo11n.pt"

# Supported YOLO models for AR
AR_SUPPORTED_MODELS = [
    "yolo11n.pt",  # nano — fastest, least accurate
    "yolo11s.pt",  # small
    "yolo11m.pt",  # medium
    "yolo11l.pt",  # large
    "yolo11x.pt",  # xlarge — slowest, most accurate
]

# Extended class list for AR (subset of COCO relevant for AR overlays)
AR_CLASSES = [
    # People & vehicles
    "person", "car", "truck", "bus", "motorcycle", "bicycle",
    # Animals
    "cat", "dog", "bird", "bear", "horse", "sheep", "cow",
    "elephant", "zebra", "giraffe",
    # Furniture & outdoor
    "potted plant", "bench", "umbrella",
    # Accessories
    "handbag", "suitcase",
    # Street objects
    "fire hydrant", "stop sign", "parking meter",
    # Electronics
    "tv", "laptop", "cell phone",
    # Kitchen & dining
    "bottle", "wine glass", "cup", "fork", "knife", "spoon", "bowl",
    # Sports
    "tennis racket", "skateboard", "surfboard",
]

# Color palette for AR bounding boxes (BGR format for OpenCV)
AR_COLORS: dict[str, tuple[int, int, int]] = {
    # People
    "person":        (0, 200, 255),
    # Vehicles
    "car":           (255, 165, 0),
    "truck":         (0, 0, 255),
    "bus":           (0, 180, 180),
    "motorcycle":    (200, 100, 200),
    "bicycle":       (150, 50, 200),
    # Animals
    "cat":           (200, 0, 200),
    "dog":           (0, 200, 0),
    "bird":          (0, 150, 255),
    "bear":          (0, 50, 200),
    "horse":         (50, 200, 100),
    "sheep":         (200, 200, 100),
    "cow":           (100, 150, 50),
    "elephant":      (50, 50, 150),
    "zebra":         (150, 150, 150),
    "giraffe":       (0, 200, 200),
    # Furniture & outdoor
    "potted plant":  (0, 180, 0),
    "bench":         (128, 128, 0),
    "umbrella":      (128, 0, 128),
    # Accessories
    "handbag":       (200, 100, 50),
    "suitcase":      (100, 50, 200),
    # Street objects
    "fire hydrant":  (0, 0, 255),
    "stop sign":     (0, 0, 200),
    "parking meter": (100, 100, 100),
    # Electronics
    "tv":            (255, 255, 0),
    "laptop":        (255, 200, 0),
    "cell phone":    (255, 100, 0),
    # Kitchen & dining
    "bottle":        (0, 255, 200),
    "wine glass":    (0, 200, 255),
    "cup":           (0, 150, 200),
    "fork":          (100, 100, 200),
    "knife":         (150, 50, 50),
    "spoon":         (50, 50, 150),
    "bowl":          (200, 200, 50),
    # Sports
    "tennis racket": (200, 50, 200),
    "skateboard":    (50, 200, 200),
    "surfboard":     (200, 200, 0),
}

# Fallback color for unknown classes
DEFAULT_COLOR = (128, 128, 128)


class ARDetector:
    """Singleton AR YOLO detector — independent from the main DetectorService.

    Provides on-demand detection with its own model cache, loading state,
    progress tracking, and extended class support.
    """

    _instance: ARDetector | None = None
    _init_lock = threading.Lock()

    @classmethod
    def get_instance(cls) -> ARDetector:
        """Get or create the singleton AR detector instance."""
        if cls._instance is None:
            with cls._init_lock:
                if cls._instance is None:
                    cls._instance = cls()
        return cls._instance

    def __init__(self):
        if ARDetector._instance is not None:
            raise RuntimeError("Use ARDetector.get_instance() instead of direct instantiation")
        self._model: YOLO | None = None
        self._model_name: str = AR_DEFAULT_MODEL
        self._loading: bool = False
        self._ready: bool = False
        self._error: str | None = None
        self._lock = threading.Lock()
        self._load_time: float = 0.0
        self._model_names: dict[int, str] = {}  # class_id -> class_name

    @property
    def model_name(self) -> str:
        """Currently loaded model name."""
        return self._model_name

    @property
    def model_names(self) -> dict[int, str]:
        """Class ID -> name mapping from the loaded model."""
        return self._model_names.copy()

    @property
    def status(self) -> dict[str, Any]:
        """Current loading/ready state.

        Returns:
            {
                'loading': bool,
                'ready': bool,
                'error': str | None,
                'model_name': str,
                'load_time_ms': float,
                'num_classes': int,
            }
        """
        return {
            "loading": self._loading,
            "ready": self._ready,
            "error": self._error,
            "model_name": self._model_name,
            "load_time_ms": self._load_time,
            "num_classes": len(self._model_names),
        }

    def load_model(
        self,
        model_name: str = AR_DEFAULT_MODEL,
        on_status: Callable[[str], None] | None = None,
    ) -> bool:
        """Load a YOLO model for AR detection.

        Args:
            model_name: YOLO model file (e.g. 'yolo11n.pt').
            on_status: Optional callback receiving status messages like
                       'Loading...', 'Model loaded (80 classes)', etc.

        Returns:
            True if model loaded successfully, False otherwise.
        """
        if model_name not in AR_SUPPORTED_MODELS:
            msg = f"Unsupported AR model: {model_name}. Supported: {AR_SUPPORTED_MODELS}"
            log.error(msg)
            if on_status:
                on_status(msg)
            with self._lock:
                self._error = msg
            return False

        with self._lock:
            if self._loading:
                log.info("AR model load already in progress, skipping")
                return False
            self._loading = True
            self._error = None
            self._ready = False

        def _do_load():
            start = time.monotonic()
            try:
                if on_status:
                    on_status(f"Loading AR model: {model_name}...")
                log.info("AR detector: loading model %s", model_name)

                # Check for local model file first
                model_path = Path(__file__).parent.parent.parent / model_name
                resolved = str(model_path) if model_path.exists() else model_name
                model = YOLO(resolved)

                elapsed = (time.monotonic() - start) * 1000  # ms

                with self._lock:
                    self._model = model
                    self._model_name = model_name
                    self._model_names = {int(k): str(v) for k, v in model.names.items()}
                    self._ready = True
                    self._loading = False
                    self._load_time = elapsed

                log.info(
                    "AR detector: model %s loaded in %.1fms (%d classes)",
                    model_name, elapsed, len(self._model_names),
                )
                if on_status:
                    on_status(f"AR model loaded: {model_name} ({len(self._model_names)} classes, {elapsed:.0f}ms)")

            except Exception as e:
                elapsed = (time.monotonic() - start) * 1000
                err_msg = f"Failed to load AR model {model_name}: {e}"
                log.error(err_msg)
                with self._lock:
                    self._error = err_msg
                    self._loading = False
                    self._ready = False
                if on_status:
                    on_status(err_msg)

        thread = threading.Thread(target=_do_load, daemon=True, name=f"ar-load-{model_name}")
        thread.start()
        # Wait briefly for fast models (nano loads in <1s usually)
        thread.join(timeout=10.0)
        return self._ready

    def detect(
        self,
        frame: np.ndarray,
        targets: list[str] | None = None,
        min_conf: float = 0.2,
        draw_boxes: bool = True,
    ) -> dict[str, Any] | None:
        """Run YOLO detection on a single frame.

        Args:
            frame: BGR numpy array (from cv2).
            targets: Optional list of class names to filter. If None, all classes
                     in AR_CLASSES are included. If provided, only matching
                     classes are returned (but all are drawn if draw_boxes=True).
            min_conf: Minimum confidence threshold (default 0.2 for AR).
            draw_boxes: Whether to annotate the frame with bounding boxes.

        Returns:
            {
                'image': bytes (JPEG-encoded annotated frame),
                'detections': [
                    {'class': str, 'confidence': float, 'bbox': [x1,y1,x2,y2]},
                    ...
                ],
                'model': str (model name used),
                'frame_size': [width, height],
            }
            Returns None if model not ready or detection fails.
        """
        with self._lock:
            if not self._ready or self._model is None:
                log.warning("AR detector: model not ready, cannot detect")
                return None
            model = self._model

        try:
            results = model(frame, conf=min_conf, verbose=False)
        except Exception as e:
            log.error("AR detection failed: %s", e)
            return None

        if not results or results[0].boxes is None:
            # No detections — still return the frame
            annotated = frame.copy() if draw_boxes else frame
            ret, jpeg = cv2.imencode(".jpg", annotated, [cv2.IMWRITE_JPEG_QUALITY, 85])
            if not ret:
                return None
            return {
                "image": jpeg.tobytes(),
                "detections": [],
                "model": self._model_name,
                "frame_size": [frame.shape[1], frame.shape[0]],
            }

        target_set = set(targets) if targets else None
        annotated = frame.copy()
        detections = []

        for box in results[0].boxes:
            class_id = int(box.cls[0].item())
            confidence = float(box.conf[0].item())
            class_name = results[0].names[class_id].lower()

            x1, y1, x2, y2 = map(int, box.xyxy[0].tolist())

            # Always collect detection data (for the response)
            is_target = target_set is None or class_name in target_set

            if is_target:
                detections.append({
                    "class": class_name,
                    "confidence": round(confidence, 3),
                    "bbox": [x1, y1, x2, y2],
                })

            # Draw boxes for target classes (or all if no filter)
            if draw_boxes and is_target:
                color = AR_COLORS.get(class_name, DEFAULT_COLOR)
                cv2.rectangle(annotated, (x1, y1), (x2, y2), color, 2)

                # Label background
                label = f"{class_name} {confidence:.0%}"
                (tw, th), baseline = cv2.getTextSize(
                    label, cv2.FONT_HERSHEY_SIMPLEX, 0.5, 1
                )
                label_y = max(y1, th + 8)
                cv2.rectangle(
                    annotated,
                    (x1, label_y - th - 6),
                    (x1 + tw + 4, label_y),
                    color,
                    -1,
                )
                cv2.putText(
                    annotated,
                    label,
                    (x1 + 2, label_y - 4),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.5,
                    (255, 255, 255),
                    1,
                )

        # Encode to JPEG
        ret, jpeg = cv2.imencode(".jpg", annotated, [cv2.IMWRITE_JPEG_QUALITY, 85])
        if not ret:
            log.error("AR detector: JPEG encode failed")
            return None

        return {
            "image": jpeg.tobytes(),
            "detections": detections,
            "model": self._model_name,
            "frame_size": [frame.shape[1], frame.shape[0]],
        }

    def detect_to_base64(
        self,
        frame: np.ndarray,
        targets: list[str] | None = None,
        min_conf: float = 0.2,
    ) -> dict[str, Any] | None:
        """Run detection and return base64-encoded image (for API responses).

        Same as detect() but encodes the JPEG to base64 string.
        """
        result = self.detect(frame, targets=targets, min_conf=min_conf, draw_boxes=True)
        if result is None:
            return None
        result["image"] = base64.b64encode(result["image"]).decode("ascii")
        return result

    def get_supported_models(self) -> list[str]:
        """Return list of supported YOLO model names."""
        return AR_SUPPORTED_MODELS.copy()

    def get_ar_classes(self) -> list[str]:
        """Return the extended AR class list."""
        return AR_CLASSES.copy()

    def reset(self):
        """Unload model and reset state. Useful for switching models."""
        with self._lock:
            self._model = None
            self._model_name = AR_DEFAULT_MODEL
            self._model_names = {}
            self._ready = False
            self._loading = False
            self._error = None
            self._load_time = 0.0
        log.info("AR detector: reset (model unloaded)")

    @classmethod
    def _reset_singleton(cls):
        """Reset the singleton (for testing)."""
        with cls._init_lock:
            if cls._instance is not None:
                cls._instance.reset()
                cls._instance = None
