"""Camera CRUD endpoints — requires Supabase auth."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from src.auth import verify_token
from src.db import get_db
from src.models import CameraOut, CameraUpdate

router = APIRouter(tags=["cameras"])


@router.get("/cameras", response_model=list[CameraOut])
async def list_cameras(user: dict = Depends(verify_token)):
    """Get all cameras for the authenticated user."""
    db = get_db()
    # Query cameras visible to this user via Supabase RLS
    result = db.table("cameras").select("*").execute()
    return result.data or []


@router.get("/cameras/{camera_id}", response_model=CameraOut)
async def get_camera(camera_id: str, user: dict = Depends(verify_token)):
    db = get_db()
    result = db.table("cameras").select("*").eq("id", camera_id).execute()
    if not result.data:
        raise HTTPException(status_code=404, detail="Camera not found")
    return result.data[0]


@router.patch("/cameras/{camera_id}", response_model=CameraOut)
async def update_camera(
    camera_id: str,
    update: CameraUpdate,
    user: dict = Depends(verify_token),
):
    db = get_db()
    payload = update.model_dump(exclude_none=True)
    if not payload:
        raise HTTPException(status_code=400, detail="No fields to update")
    result = db.table("cameras").update(payload).eq("id", camera_id).execute()
    if not result.data:
        raise HTTPException(status_code=404, detail="Camera not found")
    return result.data[0]
