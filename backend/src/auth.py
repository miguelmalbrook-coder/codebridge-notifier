"""Supabase JWT verification middleware for FastAPI."""

from __future__ import annotations

from fastapi import Header, HTTPException, status
from supabase import create_client

from src.config import settings


def verify_token(authorization: str = Header("")) -> dict:
    """Verify a Supabase JWT from the Authorization header.

    Returns the decoded user dict on success.
    Raises 401 on missing/invalid tokens.
    """
    if not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or malformed Authorization header",
        )
    token = authorization.removeprefix("Bearer ")

    try:
        client = create_client(settings.supabase_url, settings.supabase_anon_key)
        user = client.auth.get_user(token)
        return user.model_dump() if hasattr(user, "model_dump") else {"id": str(user.id), "email": str(user.email)}
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid token: {exc}",
        )
