"""YOLO detection service — runs in a background thread.

Polls all RTSP cameras (loaded from Supabase DB), runs YOLO inference,
and triggers notifications when configured targets are detected.

Users can add/edit cameras from the Flutter app — the detector
periodically refreshes the camera list from the database.
"""

from __future__ import annotations

import asyncio
import logging
import threading
import time
from datetime import datetime, timezone
from pathlib import Path

import cv2
import numpy as np
from ultralytics import YOLO

from src.config import settings
from src.db import get_db
from src.services.notifier import Notifier
from src.services.rtsp import RTSPReader

log = logging.getLogger(__name__)

DEFAULT_MODEL = "yolo11s.pt"
CAMERA_REFRESH_INTERVAL = 30  # seconds between DB camera-list refreshes


class CooldownGate:
    """Prevents alert spam for the same class on the same camera."""

    def __init__(self, default_cooldown: float = 60.0):
        self._cooldown = default_cooldown
        self._last_alert: dict[tuple[str, str], float] = {}

    def can_alert(self, camera_alias: str, class_name: str) -> bool:
        key = (camera_alias, class_name)
        now = time.monotonic()
        last = self._last_alert.get(key, 0.0)
        if now - last >= self._cooldown:
            self._last_alert[key] = now
            return True
        return False


class DetectorService:
    """Manages YOLO detection across all cameras from Supabase DB."""

    def __init__(self):
        self._thread: threading.Thread | None = None
        self._running = False
        self._model: YOLO | None = None
        self._notifier = Notifier()
        self._gate = CooldownGate(default_cooldown=settings.cooldown_seconds)
        self._loop: asyncio.AbstractEventLoop | None = None

    def start(self) -> threading.Thread:
        self._running = True
        self._thread = threading.Thread(target=self._run, daemon=True, name="yolo-detector")
        self._thread.start()
        return self._thread

    def stop(self):
        self._running = False

    def _load_model(self) -> YOLO | None:
        try:
            if self._model is None:
                log.info("Loading YOLO model: %s", DEFAULT_MODEL)
                model_path = Path(__file__).parent.parent.parent / DEFAULT_MODEL
                self._model = YOLO(str(model_path) if model_path.exists() else DEFAULT_MODEL)
                log.info("YOLO model loaded")
            return self._model
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

    def _run(self):
        log.info("Detector thread started")
        model = self._load_model()
        if model is None:
            log.error("No YOLO model available, detector exiting")
            return

        readers: list[RTSPReader] = []
        cameras: list[dict] = []
        last_refresh = 0.0
        reader_map: dict[str, RTSPReader] = {}  # alias -> reader

        while self._running:
            now = time.monotonic()

            # Periodically refresh camera list from DB
            if now - last_refresh > CAMERA_REFRESH_INTERVAL:
                fresh = self._load_cameras_from_db()
                last_refresh = now

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
                        reader_map[cam["alias"]] = RTSPReader(cam["url"])
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
                if reader._cap is None or not reader._cap.isOpened():
                    reader.open()
                    time.sleep(1)
                    continue

                ret, frame = reader._cap.read()
                if not ret:
                    log.warning("Frame skip on %s", cam["alias"])
                    reader.release()
                    time.sleep(2)
                    continue

                # Run detection
                try:
                    results = model(frame, conf=settings.confidence_threshold, verbose=False)
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

            snapshot_path = self._save_snapshot(camera_alias, class_name, frame)
            asyncio.run_coroutine_threadsafe(
                self._notify(camera_alias, class_name, confidence, snapshot_path),
                self._get_event_loop(),
            )
            self._record_alert(camera_alias, class_name, confidence, str(snapshot_path))

    def _save_snapshot(self, camera_alias: str, class_name: str, frame: np.ndarray) -> Path:
        snap_dir = Path(settings.snapshots_dir) / camera_alias
        snap_dir.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now(tz=timezone.utc).strftime("%Y%m%d_%H%M%S_%f")[:-3]
        filename = f"{class_name}_{timestamp}.jpg"
        path = snap_dir / filename
        cv2.putText(frame, f"{class_name} detected", (10, 30),
                    cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 0), 2)
        cv2.imwrite(str(path), frame, [cv2.IMWRITE_JPEG_QUALITY, 85])
        log.debug("Snapshot saved: %s", path)
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
