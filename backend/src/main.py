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
    log.info("Cameras configured: %d", len(config.camera_list))
    log.info("Detection targets: %s", config.target_classes)

    # Import + start detector in background thread
    from src.services.detector import DetectorService

    global _detector_thread, _detector
    detector = DetectorService()
    _detector = detector
    _detector_thread = detector.start()
    log.info("Detector thread started")

    yield

    log.info("Shutting down...")
    if _detector_thread:
        detector.stop()
        log.info("Detector stopped")


app = FastAPI(
    title="Codebridge Notifier API",
    version="0.1.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# --- Inline routers to avoid circular imports ---

@app.get("/api/health")
async def health():
    return {
        "status": "ok",
        "cameras": len(config.camera_list),
        "uptime": 0.0,  # Track properly later
        "version": "0.1.0",
    }


@app.get("/api/config")
async def get_config():
    """Public config endpoint (no auth)."""
    return {
        "tunnel_url": "",  # Set via env or cloudflared
        "version": "0.1.0",
    }


@app.get("/api/cameras/{alias}/snapshot")
async def camera_snapshot(alias: str):
    """Get the latest frame from a camera as a JPEG image."""
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


# Import and include routers
from src.routers import cameras, alerts, webhooks, settings  # noqa: E402

app.include_router(cameras.router, prefix="/api")
app.include_router(alerts.router, prefix="/api")
app.include_router(webhooks.router, prefix="/api")
app.include_router(settings.router, prefix="/api")


def main():
    uvicorn.run(
        "src.main:app",
        host=config.host,
        port=config.port,
        log_level=config.log_level.lower(),
    )


if __name__ == "__main__":
    main()
