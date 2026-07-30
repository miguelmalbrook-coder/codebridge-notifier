"""YOLO detection loop — runs in a background thread.

Uses HTTP ISAPI snapshots instead of RTSP (more reliable with Hikvision cameras).
Each camera uses its own settings from the cameras table (model, confidence, targets, etc.).
"""

from __future__ import annotations

import asyncio
import logging
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

import cv2
import httpx
import numpy as np
from ultralytics import YOLO

from src.config import settings
from src.db import get_db
from src.services.notifier import Notifier
from src.services.runtime_settings import get_runtime_settings

log = logging.getLogger(__name__)

DEFAULT_MODEL = "yolo11s.pt"
CAMERA_REFRESH_INTERVAL = 5.0  # Check for settings changes every 5 seconds
DEFAULT_MOTION_SENSITIVITY = 0.001  # 0.1% of pixels changed


class CooldownGate:
    """Prevents alert spam for the same class on the same camera."""

    def __init__(self, default_cooldown: float = 60.0):
        self._cooldown = default_cooldown
        self._last_alert: dict[tuple[str, str], float] = {}

    def can_alert(self, camera_alias: str, class_name: str, camera_cooldown: int | None = None) -> bool:
        key = (camera_alias, class_name)
        now = time.monotonic()
        last = self._last_alert.get(key, 0.0)
        cd = camera_cooldown if camera_cooldown is not None else self._cooldown
        if now - last >= cd:
            self._last_alert[key] = now
            return True
        return False


def rtsp_to_snapshot_url(rtsp_url: str) -> str:
    """Convert RTSP URL to HTTP ISAPI snapshot URL.

    rtsp://admin:pass@192.168.100.45:554/Streaming/Channels/402
    →  http://192.168.100.45/ISAPI/Streaming/channels/402/picture
    """
    parsed = urlparse(rtsp_url)
    host = parsed.hostname
    parts = parsed.path.strip("/").split("/")
    channel = parts[-1] if parts else "102"
    return f"http://{host}/ISAPI/Streaming/channels/{channel}/picture"


class CameraConfig:
    """Per-camera settings loaded from Supabase cameras table."""

    def __init__(self, row: dict):
        self.alias = row["alias"]
        self.rtsp_url = row["rtsp_url"]
        self.snapshot_url = rtsp_to_snapshot_url(row["rtsp_url"])
        self.db_id = row.get("id")
        self.detection_mode = row.get("detection_mode") or "yolo"
        self.model = row.get("model") or DEFAULT_MODEL
        self.confidence = float(row.get("confidence") or 0.4)
        self.cooldown = int(row.get("cooldown_seconds") or 15)
        self.targets = row.get("targets") or ["person", "car", "cat", "dog"]
        self.motion_sensitivity = float(row.get("motion_sensitivity") or DEFAULT_MOTION_SENSITIVITY)
        # Per-class confidence: dict like {"car": 0.3, "person": 0.6}
        self.class_confidences = (row.get("class_confidences") or {}) if isinstance(row.get("class_confidences"), dict) else {}

    @classmethod
    def from_db_row(cls, row: dict) -> CameraConfig | None:
        if not row.get("rtsp_url"):
            return None
        return cls(row)

    def __repr__(self):
        return f"<Camera {self.alias} mode={self.detection_mode} model={self.model} conf={self.confidence}>"


class DetectorService:
    """Manages YOLO detection across all cameras from Supabase DB.

    Each camera uses its own settings stored in the cameras table.
    The global runtime_settings API is only used for fallback defaults.
    """

    def __init__(self):
        self._running = False
        self._paused = False
        self._thread: threading.Thread | None = None
        self._model_cache: dict[str, YOLO] = {}  # model_name -> loaded model
        self._camera_statuses: dict[str, str] = {}
        self._notifier = Notifier()
        self._gate = CooldownGate(default_cooldown=15)
        self._loop: asyncio.AbstractEventLoop | None = None
        self.latest_frames: dict[str, np.ndarray] = {}
        self._bg_subtractors: dict[str, cv2.BackgroundSubtractor] = {}
        self._last_snapshot_frame_id = 0
        self._last_rel_path = ""
        self._last_full_path = None
        self._last_snapshot_camera = ""

    @property
    def is_paused(self) -> bool:
        return self._paused

    def pause(self):
        """Temporarily pause detection (keeps thread alive, stops processing)."""
        self._paused = True
        log.info("Detector PAUSED by user")

    def resume(self):
        """Resume detection after pause."""
        self._paused = False
        log.info("Detector RESUMED by user")

    def start(self) -> threading.Thread:
        self._running = True
        self._thread = threading.Thread(target=self._run, daemon=True, name="yolo-detector")
        self._thread.start()
        return self._thread

    def stop(self):
        self._running = False

    def _load_model(self, model_name: str) -> YOLO | None:
        """Load and cache a YOLO model by name."""
        if model_name in self._model_cache:
            return self._model_cache[model_name]

        try:
            log.info("Loading YOLO model: %s", model_name)
            model_path = Path(__file__).parent.parent.parent / model_name
            model = YOLO(str(model_path) if model_path.exists() else model_name)
            self._model_cache[model_name] = model
            get_runtime_settings().set_available_targets(list(model.names.values()))
            log.info("YOLO model loaded: %s (%d classes)", model_name, len(model.names))
            return model
        except Exception as e:
            log.error("Failed to load YOLO model %s: %s", model_name, e)
            return None

    def _load_cameras_from_db(self) -> list[CameraConfig]:
        """Fetch active cameras with ALL their per-camera settings from Supabase."""
        try:
            db = get_db()
            # Try with all columns first, fall back to basic columns if new ones don't exist
            columns = "alias,rtsp_url,id,status,detection_mode,model,confidence,cooldown_seconds,targets,motion_sensitivity,class_confidences"
            result = db.table("cameras").select(columns).execute()
            cameras = result.data or []
            if cameras:
                configs = []
                for row in cameras:
                    cam = CameraConfig.from_db_row(row)
                    if cam:
                        configs.append(cam)
                log.info("Loaded %d camera(s) with per-camera settings", len(configs))
                return configs
        except Exception as e:
            err_msg = str(e)
            log.warning("Full select failed: %s", err_msg[:120])
            # Fallback: try without new columns
            try:
                db = get_db()
                result = db.table("cameras").select(
                    "alias,rtsp_url,id,status,detection_mode,model,confidence,cooldown_seconds,targets,motion_sensitivity"
                ).execute()
                cameras = result.data or []
                if cameras:
                    configs = []
                    for row in cameras:
                        row["class_confidences"] = {}
                        cam = CameraConfig.from_db_row(row)
                        if cam:
                            configs.append(cam)
                    log.info("Loaded %d camera(s) with basic settings (no class_confidences)", len(configs))
                    return configs
            except Exception as e2:
                log.warning("Fallback select also failed: %s", str(e2)[:120])

        return []

    def _update_camera_status(self, camera_id: str, status: str):
        try:
            db = get_db()
            update = {"last_seen": datetime.now(tz=timezone.utc).isoformat()}
            # Only update status if it actually changed
            if self._camera_statuses.get(camera_id) != status:
                update["status"] = status
                self._camera_statuses[camera_id] = status
            db.table("cameras").update(update).eq("id", camera_id).execute()
        except Exception as e:
            log.warning("Failed to update camera %s status: %s", camera_id, e)

    def _fetch_snapshot(self, snapshot_url: str, rtsp_url: str) -> np.ndarray | None:
        """Fetch a frame from the camera via HTTP ISAPI snapshot."""
        parsed = urlparse(rtsp_url)
        username = parsed.username or "admin"
        password = parsed.password or ""

        try:
            auth = httpx.DigestAuth(username, password)
            r = httpx.get(snapshot_url, auth=auth, timeout=10)
            if r.status_code == 200:
                buf = np.frombuffer(r.content, np.uint8)
                frame = cv2.imdecode(buf, cv2.IMREAD_COLOR)
                return frame
            else:
                log.warning("Snapshot %s returned HTTP %d", snapshot_url, r.status_code)
                return None
        except Exception as e:
            log.warning("Snapshot fetch failed %s: %s", snapshot_url, e)
            return None

    def _get_tunnel_base_url(self) -> str:
        """Get the public base URL for image links in push notifications."""
        try:
            db = get_db()
            result = db.table("app_config").select("tunnel_url").limit(1).execute()
            if result.data and result.data[0].get("tunnel_url"):
                return result.data[0]["tunnel_url"]
        except Exception:
            pass
        return f"http://{settings.host}:{settings.port}"

    def _get_access_token(self) -> str | None:
        """Get a token for snapshot URLs in notifications (Supabase anon key).
        
        Devices that receive ntfy notifications use this token to access
        protected snapshot images without a user session.
        """
        return settings.supabase_anon_key

    def detect_single(self, camera_alias: str, targets: list[str] | None = None) -> dict | None:
        """Run YOLO on a single frame and return annotated JPEG bytes + detections.
        
        Used by the AR endpoint for on-demand detection.
        Returns {"image": bytes, "detections": list[dict]} or None if no frame.
        """
        if camera_alias not in self.latest_frames:
            return None

        frame = self.latest_frames[camera_alias]
        
        # Find the camera config to get model info
        cam_config = None
        for cam in self._load_cameras_from_db():
            if cam.alias == camera_alias:
                cam_config = cam
                break
        
        model_name = cam_config.model if cam_config else DEFAULT_MODEL
        model = self._load_model(model_name)
        if model is None:
            return None

        target_set = set(targets) if targets else None
        min_conf = 0.2  # Low threshold for AR — user filters visually

        try:
            results = model(frame, conf=min_conf, verbose=False)
        except Exception as e:
            log.error("AR detection error on %s: %s", camera_alias, e)
            return None

        # Annotate frame
        annotated = frame.copy()
        detections = []
        if results and results[0].boxes is not None:
            for box in results[0].boxes:
                class_id = int(box.cls[0].item())
                confidence = float(box.conf[0].item())
                class_name = results[0].names[class_id].lower()
                
                # Only draw boxes for target classes
                if target_set and class_name not in target_set:
                    continue

                x1, y1, x2, y2 = map(int, box.xyxy[0].tolist())
                color_map = {
                    'person': (255, 200, 0), 'car': (0, 165, 255),
                    'cat': (200, 0, 200), 'dog': (0, 200, 0),
                    'truck': (0, 0, 255), 'bus': (0, 180, 180),
                    'motorcycle': (200, 100, 200), 'bicycle': (150, 50, 200),
                }
                color = color_map.get(class_name, (128, 128, 128))
                cv2.rectangle(annotated, (x1, y1), (x2, y2), color, 2)
                label = f"{class_name} {confidence:.0%}"
                (tw, th), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.5, 1)
                cv2.rectangle(annotated, (x1, y1 - th - 8), (x1 + tw + 4, y1), color, -1)
                cv2.putText(annotated, label, (x1 + 2, y1 - 4),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)
                detections.append({
                    "class": class_name,
                    "confidence": round(confidence, 3),
                    "bbox": [x1, y1, x2, y2],
                })

        # Encode to JPEG
        ret, jpeg = cv2.imencode(".jpg", annotated, [cv2.IMWRITE_JPEG_QUALITY, 85])
        if not ret:
            return None

        return {"image": jpeg.tobytes(), "detections": detections}

    def _run(self):
        log.info("Detector thread started")

        cameras: list[CameraConfig] = []
        last_refresh = 0.0

        while self._running:
            # If paused, just sleep and skip all processing
            if self._paused:
                time.sleep(1)
                continue

            now = time.monotonic()

            if now - last_refresh > CAMERA_REFRESH_INTERVAL:
                cameras = self._load_cameras_from_db()
                last_refresh = now

            if not cameras:
                time.sleep(5)
                continue

            for cam in cameras:
                if not self._running:
                    break

                # Fetch frame via HTTP snapshot
                frame = self._fetch_snapshot(cam.snapshot_url, cam.rtsp_url)
                if frame is None:
                    time.sleep(1)
                    continue

                if cam.db_id:
                    self._update_camera_status(cam.db_id, "online")
                self.latest_frames[cam.alias] = frame

                # Motion gate — skip YOLO if nothing moves in "motion" mode
                if cam.detection_mode == "motion":
                    if cam.alias not in self._bg_subtractors:
                        self._bg_subtractors[cam.alias] = cv2.createBackgroundSubtractorMOG2()
                    fg = self._bg_subtractors[cam.alias].apply(frame)
                    fg = cv2.erode(fg, None, iterations=1)
                    fg = cv2.dilate(fg, None, iterations=2)
                    motion = cv2.countNonZero(fg) / (frame.shape[0] * frame.shape[1])
                    if motion < cam.motion_sensitivity:
                        continue

                # Load the per-camera model (cached)
                model = self._load_model(cam.model)
                if model is None:
                    continue

                # Run detection
                try:
                    # Use the lowest confidence threshold so all classes are detected
                    min_conf = min(cam.class_confidences.values()) if cam.class_confidences else cam.confidence
                    results = model(frame, conf=min_conf, verbose=False)
                    total = len(results[0].boxes) if results[0].boxes else 0
                    target_matches = 0
                    if total > 0:
                        for box in results[0].boxes:
                            cls = results[0].names[int(box.cls[0])].lower()
                            if cls in set(cam.targets):
                                target_matches += 1
                        if target_matches > 0:
                            log.debug("Frame %s: %d target(s) found", cam.alias, target_matches)
                    self._process_results(cam, results, frame)
                except Exception as e:
                    log.error("Detection error on %s: %s", cam.alias, e)

            time.sleep(0.5)

        log.info("Detector thread stopped")

    def _process_results(self, cam: CameraConfig, detections, frame: np.ndarray):
        if detections is None or not detections or not hasattr(detections[0], 'boxes') or detections[0].boxes is None:
            return

        targets = set(cam.targets)
        boxes = detections[0].boxes
        names = detections[0].names
        frame_id = id(frame)
        saved_snapshot = False

        for box in boxes:
            class_id = int(box.cls[0].item())
            confidence = float(box.conf[0].item())
            class_name = names[class_id].lower()

            if class_name not in targets:
                continue

            # Per-class confidence check
            class_conf = cam.class_confidences.get(class_name)
            if class_conf is not None and confidence < class_conf:
                continue

            if not self._gate.can_alert(cam.alias, class_name, cam.cooldown):
                continue

            log.info("ALERT [%s] %s @ %.2f", cam.alias, class_name, confidence)

            # Save annotated snapshot once per frame
            if not saved_snapshot or self._last_snapshot_frame_id != frame_id:
                snapshot_path = self._save_snapshot(cam.alias, detections[0], frame, targets)
                self._last_snapshot_frame_id = frame_id
                self._last_rel_path = f"{cam.alias}/{snapshot_path.name}"
                self._last_full_path = snapshot_path
                saved_snapshot = True

            # Record alert in DB (one per class per frame)
            self._record_alert(cam.alias, class_name, confidence, self._last_full_path)

            # Send push and debug notifications (synchronous — we're in a thread)
            self._notify(cam.alias, class_name, confidence, self._last_full_path)

    def _save_snapshot(self, camera_alias: str, results, frame: np.ndarray, target_set: set | None = None) -> Path:
        """Save an annotated snapshot to disk. Only annotates target classes if target_set provided."""
        annotated = frame.copy()
        all_boxes = results.boxes
        target_set = target_set or set()
        for box in all_boxes:
            class_id = int(box.cls[0].item())
            confidence = float(box.conf[0].item())
            class_name = results.names[class_id]
            # Only draw boxes for target classes (or all if no target_set)
            if target_set and class_name.lower() not in target_set:
                continue
            x1, y1, x2, y2 = map(int, box.xyxy[0].tolist())
            color = (0, 255, 0) if class_name == "person" else (255, 165, 0)
            cv2.rectangle(annotated, (x1, y1), (x2, y2), color, 2)
            label = f"{class_name} {confidence:.0%}"
            cv2.putText(annotated, label, (x1, y1 - 10),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2)

        h, w = annotated.shape[:2]
        bar_h = 30
        caption_bar = np.zeros((bar_h, w, 3), dtype=np.uint8)
        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        caption = f"{camera_alias} | {ts}"
        cv2.putText(caption_bar, caption, (10, 20),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)
        annotated = np.vstack([annotated, caption_bar])

        snap_dir = Path("/app/snapshots") / camera_alias
        snap_dir.mkdir(parents=True, exist_ok=True)
        ts_file = datetime.now(tz=timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
        filename = f"alert_{ts_file}.jpg"
        filepath = snap_dir / filename

        ret, jpeg = cv2.imencode(".jpg", annotated, [cv2.IMWRITE_JPEG_QUALITY, 85])
        if ret:
            filepath.write_bytes(jpeg.tobytes())
            log.info("Snapshot saved: %s", filepath)

        return filepath

    def _record_alert(self, camera_alias: str, class_name: str, confidence: float, snapshot_path: Path):
        """Insert a single alert record into Supabase."""
        try:
            db = get_db()
            rel_path = f"{camera_alias}/{snapshot_path.name}"

            db.table("alerts").insert({
                "camera_id": camera_alias,
                "class_name": class_name,
                "confidence": round(confidence, 3),
                "snapshot_url": rel_path,
                "seen_at": datetime.now(tz=timezone.utc).isoformat(),
            }).execute()
        except Exception as e:
            log.warning("Failed to record alert: %s", e)

    def _get_event_loop(self) -> asyncio.AbstractEventLoop:
        if self._loop is None or self._loop.is_closed():
            try:
                self._loop = asyncio.get_running_loop()
            except RuntimeError:
                self._loop = asyncio.new_event_loop()
                asyncio.set_event_loop(self._loop)
        return self._loop

    def _notify(self, camera_alias, class_name, confidence, snapshot_path):
        base_url = self._get_tunnel_base_url()
        title = f"🚨 {class_name.title()} at {camera_alias.title()}"
        body = f"{confidence:.0%} confidence"

        image_url = None
        if snapshot_path and snapshot_path.exists():
            rel = f"{camera_alias}/{snapshot_path.name}"
            # Include a public access token so the image loads in notifications
            token = self._get_access_token()
            token_suffix = f"?token={token}" if token else ""
            image_url = f"{base_url}/api/snapshots/{rel}{token_suffix}"
        self._notifier.send_ntfy(title, body, image_url=image_url)

        # FCM push (WhatsApp-level — works when app is killed)
        try:
            from src.services.fcm import FCMPusher
            fcm = FCMPusher()
            fcm.send_to_all_devices(
                title=title,
                body=body,
                image_url=image_url,
                data={"camera": camera_alias, "class": class_name, "confidence": str(round(confidence, 2))},
            )
        except Exception as e:
            log.warning("FCM push error: %s", e)

        # Telegram debug alerts — temporarily disabled
        # if settings.has_telegram:
        #     text = (
        #         f"<b>🚨 DETECTION</b>\n"
        #         f"Camera: {camera_alias}\n"
        #         f"Object: {class_name}\n"
        #         f"Confidence: {confidence:.0%}\n"
        #         f"Time: {datetime.now(tz=timezone.utc).isoformat()}"
        #     )
        #     self._notifier.send_telegram(text)
        #     if snapshot_path and snapshot_path.exists():
        #         self._notifier.send_telegram_photo(
        #             snapshot_path, caption=f"{class_name} @ {camera_alias}"
        #         )
