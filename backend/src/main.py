"""FastAPI app entrypoint — registers routers and starts detection."""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

import cv2

from src.config import settings as config

logging.basicConfig(
    level=getattr(logging, config.log_level.upper(), logging.INFO),
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
log = logging.getLogger(__name__)
_detector_thread = None
_detector = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Start YOLO detector on startup, clean up on shutdown."""
    log.info("Starting Codebridge Notifier API...")

    # Import + start detector in background thread
    from src.services.detector import DetectorService

    global _detector_thread, _detector
    detector = DetectorService()
    _detector = detector
    _detector_thread = detector.start()
    log.info("Detector thread started")

    # Pre-load YOLO model so available_targets are populated immediately
    try:
        from ultralytics import YOLO
        m = YOLO("yolo11n.pt")
        names = list(m.names.values())
        from src.services.runtime_settings import get_runtime_settings
        get_runtime_settings().set_available_targets(names)
        log.info("Pre-loaded YOLO model with %d classes", len(names))
    except Exception as e:
        log.warning("Could not pre-load YOLO model: %s", e)

    yield

    log.info("Shutting down...")
    if _detector_thread:
        detector.stop()
        log.info("Detector stopped")


app = FastAPI(
    title="Codebridge Notifier API",
    version="0.3.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/api/health")
async def health():
    """Health check — returns camera count and subscription status."""
    try:
        from src.db import get_db
        db = get_db()
        result = db.table("cameras").select("id").execute()
        cam_count = len(result.data or [])
    except Exception:
        cam_count = 0

    return {
        "status": "ok",
        "cameras": cam_count,
        "version": "0.3.0",
    }


@app.get("/api/config")
async def get_config():
    """Public config — reads tunnel URL and subscription from Supabase."""
    try:
        from src.db import get_db
        db = get_db()
        # Read from a settings/config table
        result = db.table("app_config").select("*").execute()
        data = result.data[0] if result.data else {}
        return {
            "tunnel_url": data.get("tunnel_url", ""),
            "subscribed": data.get("subscribed", False),
            "version": "0.3.0",
        }
    except Exception:
        return {
            "tunnel_url": "",
            "subscribed": False,
            "version": "0.3.0",
        }


@app.get("/api/cameras/{alias}/snapshot")
async def camera_snapshot(alias: str):
    """Get the latest frame from a camera as a JPEG image.
    
    NOTE: This endpoint is intentionally public for live-view in the app.
    The try.cloudflare.com URL rotates on restart, providing ephemeral security.
    """
    from fastapi.responses import Response

    if _detector is None or alias not in _detector.latest_frames:
        from fastapi import HTTPException
        raise HTTPException(status_code=404, detail="No snapshot available")

    frame = _detector.latest_frames[alias]
    ret, jpeg = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 85])
    if not ret:
        from fastapi import HTTPException
        raise HTTPException(status_code=500, detail="Failed to encode frame")

    return Response(content=jpeg.tobytes(), media_type="image/jpeg")


@app.get("/app-release.apk")
async def download_apk():
    """Serve the latest Flutter APK for download."""
    from fastapi.responses import FileResponse
    from fastapi import HTTPException
    from pathlib import Path

    apk_path = Path("/app/app-release.apk")
    if not apk_path.exists():
        raise HTTPException(status_code=404, detail="APK not found")
    return FileResponse(str(apk_path), media_type="application/vnd.android.package-archive", filename="codebridge-notifier.apk")


# Import and include routers
from src.routers import cameras, alerts, webhooks, settings as settings_router  # noqa: E402

app.include_router(cameras.router, prefix="/api")
app.include_router(alerts.router, prefix="/api")
app.include_router(webhooks.router, prefix="/api")
app.include_router(settings_router.router, prefix="/api")


def main():
    uvicorn.run(
        "src.main:app",
        host=config.host,
        port=config.port,
        log_level=config.log_level.lower(),
    )


if __name__ == "__main__":
    main()
