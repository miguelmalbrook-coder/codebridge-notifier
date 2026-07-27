"""Supabase JWT verification middleware for FastAPI.

Accepts token via Authorization header (primary) or `token` query param (fallback
for Flutter Image.network which can't set custom headers).
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

    Returns the decoded user dict on success. Raises 401 on invalid tokens.
    """
    jwt = _extract_jwt(authorization, token)
    if jwt is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or malformed Authorization header",
        )

    try:
        client = create_client(settings.supabase_url, settings.supabase_anon_key)
        user = client.auth.get_user(jwt)
        return user.model_dump() if hasattr(user, "model_dump") else {"id": str(user.id), "email": str(user.email)}
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid token: {exc}",
        )


def _extract_jwt(authorization: str, token_param: str | None) -> str | None:
    """Try Authorization header first, then query param."""
    if authorization.startswith("Bearer "):
        return authorization.removeprefix("Bearer ")
    if token_param and len(token_param) > 20:
        return token_param
    return None
