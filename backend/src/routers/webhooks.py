"""Webhooks — FCM device registration. Push is triggered internally."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from src.auth import verify_token
from src.db import get_db
from src.models import RegisterDeviceRequest, RegisterDeviceResponse

router = APIRouter(tags=["webhooks"])


@router.post("/devices/register", response_model=RegisterDeviceResponse)
async def register_device(
    body: RegisterDeviceRequest,
    user: dict = Depends(verify_token),
):
    """Register a device FCM token for push notifications."""
    db = get_db()
    # Extract user ID from various possible JWT formats
    user_id = (user.get("sub") or user.get("id") or user.get("user_id") or "")
    if not user_id:
        raise HTTPException(status_code=400, detail="Could not extract user ID from token")

    # Upsert: remove old token + insert new
    db.table("device_tokens").delete().eq("token", body.token).execute()
    db.table("device_tokens").insert({
        "user_id": user_id,
        "token": body.token,
        "platform": body.platform,
    }).execute()

    return RegisterDeviceResponse(success=True)


@router.post("/devices/unregister", response_model=RegisterDeviceResponse)
async def unregister_device(
    body: RegisterDeviceRequest,
    user: dict = Depends(verify_token),
):
    """Remove a device FCM token."""
    db = get_db()
    db.table("device_tokens").delete().eq("token", body.token).execute()
    return RegisterDeviceResponse(success=True, message="Device unregistered")
