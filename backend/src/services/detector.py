"""YOLO detection service — runs in a background thread.

Polls all RTSP cameras (loaded from Supabase DB), runs YOLO inference,
and triggers notifications when configured targets are detected.

Users can add/edit cameras from the Flutter app — the detector
periodically refreshes the camera list from the database.
"""

from __future__ import annotations

import asyncio
import logging
import os
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from ultralytics import YOLO

from src.config import settings
from src.db import get_db
from src.services.notifier import Notifier
from src.services.rtsp import create_reader
from src.services.runtime_settings import get_runtime_settings

log = logging.getLogger(__name__)

DEFAULT_MODEL = "yolo11s.pt"
CAMERA_REFRESH_INTERVAL = 30.0
model_names: dict[int, str] = {}  # id(model) -> model name


class CooldownGate:
    """Prevents alert spam for the same class on the same camera."""

    def __init__(self, default_cooldown: float = 60.0):
        self._cooldown = default_cooldown
        self._last_alert: dict[tuple[str, str], float] = {}

    def can_alert(self, camera_alias: str, class_name: str) -> bool:
        key = (camera_alias, class_name)
        now = time.monotonic()
        last = self._last_alert.get(key, 0.0)
        # Use runtime settings cooldown (default to instance cooldown)
        cd = get_runtime_settings().cooldown if get_runtime_settings() else self._cooldown
        if now - last >= cd:
            self._last_alert[key] = now
            return True
        return False


class DetectorService:
    """Manages YOLO detection across all cameras from Supabase DB."""

    def __init__(self):
        self._running = False
        self._thread: threading.Thread | None = None
        self._model: YOLO | None = None
        self._camera_statuses: dict[str, str] = {}  # cam_id -> last status
        self._notifier = Notifier()
        self._gate = CooldownGate(default_cooldown=settings.cooldown_seconds)
        self._loop: asyncio.AbstractEventLoop | None = None
        self.latest_frames: dict[str, np.ndarray] = {}  # alias -> frame
        self._bg_subtractors: dict[str, cv2.BackgroundSubtractor] = {}  # alias -> MOG2
        self._last_snapshot_frame = None
        self._last_rel_path = ""
        self._last_full_path = None

    def start(self) -> threading.Thread:
        self._running = True
        self._thread = threading.Thread(target=self._run, daemon=True, name="yolo-detector")
        self._thread.start()
        return self._thread

    def stop(self):
        self._running = False

    def _load_model(self, model_name: str | None = None) -> YOLO | None:
        try:
            name = model_name or get_runtime_settings().model or DEFAULT_MODEL
            log.info("Loading YOLO model: %s", name)
            model_path = Path(__file__).parent.parent.parent / name
            model = YOLO(str(model_path) if model_path.exists() else name)
            model_names[id(model)] = name
            log.info("YOLO model loaded: %s", name)
            return model
        except Exception as e:
            log.error("Failed to load YOLO model: %s", e)
            return None

    def _load_cameras_from_db(self) -> list[dict]:
        """Fetch active cameras from Supabase DB.

        Returns a list of dicts with keys: alias, rtsp_url, id.
        Falls back to env-var cameras if DB is unreachable.
        """
        try:
            db = get_db()
            result = db.table("cameras").select("alias,rtsp_url,id,status").execute()
            cameras = result.data or []
            if cameras:
                log.info("Loaded %d camera(s) from Supabase", len(cameras))
                return [
                    {"alias": c["alias"], "url": c["rtsp_url"], "id": c["id"]}
                    for c in cameras
                    if c.get("rtsp_url")
                ]
        except Exception as e:
            log.warning("Could not load cameras from DB: %s", e)

        # Fallback: env-var cameras
        env_cams = settings.camera_list
        if env_cams:
            log.info("Falling back to %d env-var camera(s)", len(env_cams))
        return env_cams

    def _update_camera_status(self, camera_id: str, status: str):
        """Update a camera's status and last_seen in Supabase (only if changed)."""
        if self._camera_statuses.get(camera_id) == status:
            return  # Skip if already in this state
        try:
            from src.db import get_db
            db = get_db()
            db.table("cameras").update({
                "status": status,
                "last_seen": datetime.now(tz=timezone.utc).isoformat(),
            }).eq("id", camera_id).execute()
            self._camera_statuses[camera_id] = status
        except Exception as e:
            log.warning("Failed to update camera %s status: %s", camera_id, e)

    def _reader_ready(self, reader: Any) -> bool:
        """Check if a reader is ready to provide frames."""
        if hasattr(reader, "_cap"):
            return reader._cap is not None and reader._cap.isOpened()
        # SnapshotReader and similar stateless readers are always ready
        return True

    def _read_frame(self, reader: Any, alias: str) -> np.ndarray | None:
        """Read one frame from any reader type. Returns None on failure."""
        if hasattr(reader, "read_frame"):
            return reader.read_frame()
        # RTSPReader path
        try:
            ret, frame = reader._cap.read()
            if ret:
                return frame
            log.warning("Frame skip on %s", alias)
        except Exception as e:
            log.warning("Read error on %s: %s", alias, e)
        return None

    def _run(self):
        log.info("Detector thread started")
        model = self._load_model()
        if model is None:
            log.error("No YOLO model available, detector exiting")
            return

        readers: list = []
        cameras: list[dict] = []
        last_refresh = 0.0
        reader_map: dict[str, Any] = {}  # alias -> reader

        while self._running:
            now = time.monotonic()

            # Periodically refresh camera list from DB
            if now - last_refresh > CAMERA_REFRESH_INTERVAL:
                fresh = self._load_cameras_from_db()
                last_refresh = now

                # Check for runtime model change
                requested = get_runtime_settings().model
                if model is not None and requested != model_names.get(id(model), ""):
                    log.info("Model change requested: %s -> %s", model_names.get(id(model)), requested)
                    new_model = self._load_model(requested)
                    if new_model is not None:
                        model = new_model
                    else:
                        log.warning("Failed to load model %s, keeping current", requested)

                # Detect added / removed cameras
                fresh_aliases = {c["alias"] for c in fresh}
                old_aliases = {c["alias"] for c in cameras}

                # Release readers for removed cameras
                for alias in old_aliases - fresh_aliases:
                    if alias in reader_map:
                        reader_map[alias].release()
                        del reader_map[alias]
                        log.info("Removed camera: %s", alias)

                # Add readers for new cameras
                for cam in fresh:
                    if cam["alias"] not in reader_map:
                        reader_map[cam["alias"]] = create_reader(cam["url"])
                        log.info("Added camera: %s -> %s", cam["alias"], cam["url"])

                cameras = fresh

            if not cameras:
                time.sleep(5)
                continue

            # Round-robin frame processing
            for cam in cameras:
                if not self._running:
                    break

                reader = reader_map.get(cam["alias"])
                if reader is None:
                    continue

                # Open reader if needed
                if not self._reader_ready(reader):
                    reader.open()
                    time.sleep(1)
                    continue

                # Read frame (handles both RTSP and Snapshot readers)
                frame = self._read_frame(reader, cam["alias"])
                if frame is None:
                    time.sleep(0.5)
                    continue

                # Mark online on first successful read
                if cam.get("id"):
                    self._update_camera_status(cam["id"], "online")
                self.latest_frames[cam["alias"]] = frame

                # Motion gate (only when mode == "motion")
                rs = get_runtime_settings()
                if rs.mode == "motion":
                    if cam["alias"] not in self._bg_subtractors:
                        self._bg_subtractors[cam["alias"]] = cv2.createBackgroundSubtractorMOG2()
                    fg = self._bg_subtractors[cam["alias"]].apply(frame)
                    fg = cv2.erode(fg, None, iterations=1)
                    fg = cv2.dilate(fg, None, iterations=2)
                    motion = cv2.countNonZero(fg) / (frame.shape[0] * frame.shape[1])
                    if motion < 0.001:  # < 0.1% changed pixels = no motion
                        continue

                # Run detection with runtime confidence
                try:
                    conf = rs.confidence
                    results = model(frame, conf=conf, verbose=False)
                    self._process_results(cam["alias"], results, frame)
                except Exception as e:
                    log.error("Detection error on %s: %s", cam["alias"], e)

            time.sleep(0.1)

        # Cleanup
        for reader in reader_map.values():
            reader.release()
        log.info("Detector thread stopped")

    def _process_results(self, camera_alias: str, results, frame: np.ndarray):
        if not results or len(results) == 0:
            return

        targets = set(settings.target_classes)
        detections = results[0]
        if detections.boxes is None:
            return

        for box in detections.boxes:
            class_id = int(box.cls[0].item())
            confidence = float(box.conf[0].item())
            class_name = detections.names[class_id].lower()

            if class_name not in targets:
                continue
            if not self._gate.can_alert(camera_alias, class_name):
                continue

            log.info("ALERT [%s] %s @ %.2f", camera_alias, class_name, confidence)

            # Save a single annotated snapshot per frame (regardless of how many detections)
            if not hasattr(self, '_last_snapshot_frame') or self._last_snapshot_frame != id(frame):
                snapshot_path = self._save_snapshot(camera_alias, detections, frame)
                self._last_snapshot_frame = id(frame)
                self._last_rel_path = f"{camera_alias}/{snapshot_path.name}"
                self._last_full_path = snapshot_path
            else:
                snapshot_path = self._last_full_path

            asyncio.run_coroutine_threadsafe(
                self._notify(camera_alias, class_name, confidence, snapshot_path),
                self._get_event_loop(),
            )
            self._record_alert(camera_alias, class_name, confidence, self._last_rel_path)

    def _save_snapshot(self, camera_alias: str, detections, frame: np.ndarray) -> Path:
        """Save a snapshot with YOLO bounding boxes, class labels, and caption."""
        snap_dir = Path(settings.snapshots_dir) / camera_alias
        snap_dir.mkdir(parents=True, exist_ok=True)
        now = datetime.now(tz=timezone.utc)
        timestamp = now.strftime("%Y%m%d_%H%M%S_%f")[:-3]
        filename = f"alert_{timestamp}.jpg"
        path = snap_dir / filename

        annotate = frame.copy()
        targets = set(settings.target_classes)

        # Colors for different classes
        colors = {
            "person": (0, 255, 0),    # green
            "car": (255, 0, 0),        # blue
            "cat": (255, 255, 0),      # cyan
            "dog": (0, 165, 255),      # orange
        }
        default_color = (0, 255, 255)  # yellow

        # Draw bounding boxes for all detections
        if detections and detections.boxes is not None:
            for box in detections.boxes:
                class_id = int(box.cls[0].item())
                conf = float(box.conf[0].item())
                name = detections.names[class_id].lower()
                if name not in targets:
                    continue

                color = colors.get(name, default_color)
                x1, y1, x2, y2 = map(int, box.xyxy[0])

                # Draw filled rectangle for label background
                label = f"{name.upper()} {conf:.0%}"
                (tw, th), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.6, 2)
                cv2.rectangle(annotate, (x1, y1), (x1 + tw + 8, y1 + th + 8), color, -1)
                # Draw box outline
                cv2.rectangle(annotate, (x1, y1), (x2, y2), color, 2)
                # Draw label text
                cv2.putText(annotate, label, (x1 + 4, y1 + th + 4),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 0), 2)

        # Caption bar at bottom
        caption_text = f"{camera_alias}  |  {now.strftime('%Y-%m-%d %H:%M:%S UTC')}"
        bar_h = 36
        h, w = annotate.shape[:2]
        cv2.rectangle(annotate, (0, h - bar_h), (w, h), (0, 0, 0), -1)
        cv2.putText(annotate, caption_text, (12, h - 10),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 1)

        cv2.imwrite(str(path), annotate, [cv2.IMWRITE_JPEG_QUALITY, 90])
        log.info("Snapshot saved: %s (%d boxes)", path, len(detections.boxes) if detections and detections.boxes is not None else 0)
        return path

    def _get_event_loop(self) -> asyncio.AbstractEventLoop:
        try:
            return asyncio.get_event_loop()
        except RuntimeError:
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            return loop

    async def _notify(self, camera_alias, class_name, confidence, snapshot_path):
        title = f"🚨 {class_name.title()} detected"
        body = f"{camera_alias} · {confidence:.0%} confidence"
        self._notifier.send_customer_push(title, body)

        if settings.has_telegram:
            text = (
                f"<b>🚨 DETECTION</b>\n"
                f"Camera: {camera_alias}\n"
                f"Object: {class_name}\n"
                f"Confidence: {confidence:.0%}\n"
                f"Time: {datetime.now(tz=timezone.utc).isoformat()}"
            )
            await self._notifier.send_telegram(text)
            if snapshot_path and snapshot_path.exists():
                await self._notifier.send_telegram_photo(
                    snapshot_path, caption=f"{class_name} @ {camera_alias}"
                )

    def _record_alert(self, camera_alias, class_name, confidence, snapshot_url):
        try:
            from src.db import get_db
            db = get_db()
            db.table("alerts").insert({
                "camera_id": camera_alias,
                "class_name": class_name,
                "confidence": round(confidence, 3),
                "snapshot_url": snapshot_url,
                "seen_at": datetime.now(tz=timezone.utc).isoformat(),
            }).execute()
        except Exception as e:
            log.warning("Failed to record alert in DB: %s", e)
