"""Runtime settings endpoint — change model, mode, targets, etc. without restart."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from src.auth import verify_token
from src.services.runtime_settings import get_runtime_settings

router = APIRouter(tags=["settings"])

AVAILABLE_MODELS = [
    "yolo11n.pt",
    "yolo11s.pt",
    "yolo11m.pt",
    "yolo11l.pt",
    "yolo11x.pt",
]


@router.get("/settings")
async def get_settings():
    """Get current runtime settings. No auth required."""
    s = get_runtime_settings()
    return {
        **s.as_dict(),
        "available_models": AVAILABLE_MODELS,
    }


@router.put("/settings")
async def update_settings(body: dict, user: dict = Depends(verify_token)):
    """Update runtime settings. Only provided fields are changed. Requires auth."""
    s = get_runtime_settings()
    errors = []

    if "mode" in body:
        try:
            s.mode = body["mode"]
        except ValueError as e:
            errors.append(str(e))

    if "model" in body:
        model = body["model"]
        if model not in AVAILABLE_MODELS:
            errors.append(
                f"Model must be one of: {', '.join(AVAILABLE_MODELS)}"
            )
        else:
            s.model = model

    if "confidence" in body:
        try:
            s.confidence = body["confidence"]
        except ValueError as e:
            errors.append(str(e))

    if "cooldown" in body:
        try:
            s.cooldown = body["cooldown"]
        except ValueError as e:
            errors.append(str(e))

    if "targets" in body:
        try:
            s.targets = body["targets"]
        except ValueError as e:
            errors.append(str(e))

    if errors:
        raise HTTPException(status_code=400, detail="; ".join(errors))

    return {"status": "ok", **s.as_dict()}
