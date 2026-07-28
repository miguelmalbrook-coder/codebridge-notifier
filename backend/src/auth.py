"""Supabase JWT verification middleware for FastAPI.

Accepts token via Authorization header (primary) or `token` query param (fallback
for Flutter Image.network which can't set custom headers).
Also accepts the Supabase anon key for public snapshot access via ntfy notifications.
"""

from __future__ import annotations

from fastapi import Header, HTTPException, Query, status
from supabase import create_client

from src.config import settings


def verify_token(
    authorization: str = Header(""),
    token: str | None = Query(None),
) -> dict:
    """Verify a Supabase JWT.

    Primary: Authorization: Bearer <token> (from fetch/XHR clients).
    Fallback: ?token=<token> query parameter (for Flutter Image.network).
    Also accepts Supabase anon key for public snapshot access.

    Returns the decoded user dict on success. Raises 401 on invalid tokens.
    """
    jwt = _extract_jwt(authorization, token, settings.supabase_anon_key)
    if jwt is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or malformed Authorization header",
        )

    # Allow anon key for snapshot access (used by ntfy notifications)
    if jwt == settings.supabase_anon_key:
        return {"id": "anon", "email": "anon@notification"}

    try:
        client = create_client(settings.supabase_url, settings.supabase_anon_key)
        user = client.auth.get_user(jwt)
        return user.model_dump() if hasattr(user, "model_dump") else {"id": str(user.id), "email": str(user.email)}
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid token: {exc}",
        )


def _extract_jwt(authorization: str, token_param: str | None, anon_key: str) -> str | None:
    """Try Authorization header first, then query param."""
    # Allow anon key in Authorization header
    if authorization == anon_key:
        return anon_key
    if authorization.startswith("Bearer "):
        bearer = authorization.removeprefix("Bearer ")
        if bearer:
            return bearer
    if token_param and len(token_param) > 20:
        return token_param
    return None
