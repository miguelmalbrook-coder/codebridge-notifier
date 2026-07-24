"""Supabase client wrapper — single point of DB access."""

from __future__ import annotations

from supabase import create_client, Client

from src.config import settings


_supabase: Client | None = None


def get_db() -> Client:
    global _supabase
    if _supabase is None:
        _supabase = create_client(
            settings.supabase_url,
            settings.supabase_service_key,
        )
    return _supabase


def get_anon_client() -> Client:
    """For client-side operations (RLS-limited)."""
    return create_client(
        settings.supabase_url,
        settings.supabase_anon_key,
    )
