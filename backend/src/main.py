"""FastAPI app entrypoint — registers routers and starts detection."""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from src.config import settings

logging.basicConfig(
    level=getattr(logging, settings.log_level.upper(), logging.INFO),
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
log = logging.getLogger(__name__)

_detector_thread = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Start YOLO detector on startup, clean up on shutdown."""
    log.info("Starting Codebridge Notifier API...")
    log.info("Cameras configured: %d", len(settings.camera_list))
    log.info("Detection targets: %s", settings.target_classes)

    # Import + start detector in background thread
    from src.services.detector import DetectorService

    global _detector_thread
    detector = DetectorService()
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
        "cameras": len(settings.camera_list),
        "uptime": 0.0,  # Track properly later
        "version": "0.1.0",
    }


@app.get("/api/config")
async def config():
    """Public config endpoint (no auth)."""
    return {
        "tunnel_url": "",  # Set via env or cloudflared
        "version": "0.1.0",
    }


# Import and include routers
from src.routers import cameras, alerts, webhooks  # noqa: E402

app.include_router(cameras.router, prefix="/api")
app.include_router(alerts.router, prefix="/api")
app.include_router(webhooks.router, prefix="/api")


def main():
    uvicorn.run(
        "src.main:app",
        host=settings.host,
        port=settings.port,
        log_level=settings.log_level.lower(),
    )


if __name__ == "__main__":
    main()
