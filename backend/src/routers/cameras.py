"""Camera CRUD endpoints — requires Supabase auth."""

from __future__ import annotations

from pathlib import Path

import httpx
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response, FileResponse

from src.auth import verify_token
from src.db import get_db
from src.models import CameraOut, CameraUpdate
from src.services.detector import rtsp_to_snapshot_url

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


@router.get("/cameras/{camera_id}/preview")
async def get_camera_preview(
    camera_id: str,
    user: dict = Depends(verify_token),
):
    """Fetch a live snapshot preview from the camera via ISAPI."""
    db = get_db()
    result = db.table("cameras").select("rtsp_url,alias").eq("id", camera_id).execute()
    if not result.data:
        raise HTTPException(status_code=404, detail="Camera not found")
    cam = result.data[0]
    rtsp_url = cam.get("rtsp_url", "")
    if not rtsp_url:
        raise HTTPException(status_code=400, detail="No RTSP URL configured")

    snapshot_url = rtsp_to_snapshot_url(rtsp_url)

    # Extract credentials from RTSP URL for ISAPI auth (Hikvision uses digest auth)
    from urllib.parse import urlparse
    parsed = urlparse(rtsp_url)
    auth = None
    if parsed.username and parsed.password:
        auth = httpx.DigestAuth(parsed.username, parsed.password)

    try:
        async with httpx.AsyncClient(timeout=8) as client:
            resp = await client.get(snapshot_url, auth=auth)
            if resp.status_code == 200 and resp.headers.get("content-type", "").startswith("image"):
                return Response(content=resp.content, media_type="image/jpeg")
            raise HTTPException(status_code=502, detail=f"Camera returned {resp.status_code}")
    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Camera timeout")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@router.get("/cameras/{camera_id}/annotated")
async def get_annotated_snapshot(
    camera_id: str,
    user: dict = Depends(verify_token),
):
    """Return the latest YOLO-annotated snapshot (with bounding boxes)."""
    db = get_db()
    result = db.table("cameras").select("alias").eq("id", camera_id).execute()
    if not result.data:
        raise HTTPException(status_code=404, detail="Camera not found")
    alias = result.data[0]["alias"]

    # Find the latest snapshot file for this camera
    snap_dir = Path("/app/snapshots") / alias
    if not snap_dir.exists():
        raise HTTPException(status_code=404, detail="No snapshots yet")

    files = sorted(snap_dir.glob("alert_*.jpg"), key=lambda f: f.stat().st_mtime, reverse=True)
    if not files:
        raise HTTPException(status_code=404, detail="No snapshots yet")

    return FileResponse(files[0], media_type="image/jpeg")


@router.get("/cameras/{camera_id}/heatmap")
async def get_heatmap(
    camera_id: str,
    hours: int = 24,
    user: dict = Depends(verify_token),
):
    """Return detection heatmap data for a camera (positions over time)."""
    from datetime import datetime, timezone, timedelta

    db = get_db()
    
    # Resolve camera alias (alerts store alias as camera_id, not UUID)
    cam_result = db.table("cameras").select("alias").eq("id", camera_id).execute()
    alias = cam_result.data[0]["alias"] if cam_result.data else camera_id
    
    since = (datetime.now(tz=timezone.utc) - timedelta(hours=hours)).isoformat()

    # Query by alias (matching how alerts are stored) OR by UUID
    result = db.table("alerts").select("seen_at,confidence,class_name").or_(
        f"camera_id.eq.{camera_id},camera_id.eq.{alias}"
    ).gte("seen_at", since).order("seen_at", desc=True).limit(500).execute()

    alerts = result.data or []

    # Group by class and hour
    by_class = {}
    for alert in alerts:
        cls = alert.get("class_name", "unknown")
        ts = alert.get("seen_at", "")
        hour = int(ts[11:13]) if len(ts) > 13 else 0
        if cls not in by_class:
            by_class[cls] = {}
        by_class[cls][hour] = by_class[cls].get(hour, 0) + 1

    # Build 24-hour heatmap per class
    heatmap = {}
    for cls, hours_data in by_class.items():
        heatmap[cls] = [{"hour": h, "count": hours_data.get(h, 0)} for h in range(24)]

    return {
        "camera_id": camera_id,
        "hours": hours,
        "total_detections": len(alerts),
        "classes": list(by_class.keys()),
        "heatmap": heatmap,
    }


@router.get("/cameras/{camera_id}/heatmap/alerts")
async def get_alerts_for_hour(
    camera_id: str,
    hour: int = 0,
    user: dict = Depends(verify_token),
):
    """Return alerts for a specific camera and hour."""
    from datetime import datetime, timezone, timedelta

    db = get_db()
    
    # Resolve camera alias
    cam_result = db.table("cameras").select("alias").eq("id", camera_id).execute()
    alias = cam_result.data[0]["alias"] if cam_result.data else camera_id
    
    # Get today's date range for the specified hour
    now = datetime.now(tz=timezone.utc)
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    hour_start = today_start + timedelta(hours=hour)
    hour_end = hour_start + timedelta(hours=1)
    
    result = db.table("alerts").select("*").or_(
        f"camera_id.eq.{camera_id},camera_id.eq.{alias}"
    ).gte("seen_at", hour_start.isoformat()).lt("seen_at", hour_end.isoformat()).order("seen_at", desc=True).limit(50).execute()
    
    return {"alerts": result.data or [], "hour": hour, "camera": alias}
