"""Alert history endpoints — requires Supabase auth."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query
from supabase import Client

from src.auth import verify_token
from src.db import get_db
from src.models import AlertList, AlertOut

router = APIRouter(tags=["alerts"])


@router.get("/alerts", response_model=AlertList)
async def list_alerts(
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    camera_id: str | None = None,
    user: dict = Depends(verify_token),
):
    """Paginated alert history for the user's cameras."""
    db: Client = get_db()
    query = db.table("alerts").select("*", count="exact")

    if camera_id:
        query = query.eq("camera_id", camera_id)

    query = query.order("seen_at", desc=True).range(
        (page - 1) * per_page, page * per_page - 1
    )
    result = query.execute()

    total = result.count or 0
    return AlertList(
        alerts=[AlertOut(**a) for a in (result.data or [])],
        total=total,
        page=page,
        per_page=per_page,
    )


@router.get("/alerts/{alert_id}", response_model=AlertOut)
async def get_alert(alert_id: str, user: dict = Depends(verify_token)):
    db = get_db()
    result = db.table("alerts").select("*").eq("id", alert_id).execute()
    if not result.data:
        raise HTTPException(status_code=404, detail="Alert not found")
    return result.data[0]
