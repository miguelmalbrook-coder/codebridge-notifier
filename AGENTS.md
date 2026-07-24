# Codebridge Notifier — AI Agent Guide

## Project Overview

A white-label camera monitoring system for Codebridge Consultancy customers.
Uses YOLO object detection on RTSP camera streams, sends push notifications
to a Flutter mobile app via FCM, and keeps Telegram for admin/debug alerts.

## Architecture (Three-Tier)

```
RTSP Camera → Docker Backend (YOLO + FastAPI) → Supabase (Auth + DB) → Flutter App
                                                      ↕
                                               FCM (Push)
                                                      ↕
                                               Telegram (Debug)
```

- **Docker** — single container per customer. Configured entirely via env vars.
- **Supabase** — auth (magic link / email), database (cameras, alerts, users),
  real-time subscriptions for live updates.
- **Flutter** — customer-facing Android app (iOS-ready). Connects to Supabase
  directly for auth + data, receives FCM pushes from the backend.
- **Telegram** — kept for sysadmin debug (service health, critical errors).

## Key Design Rules

1. **Nothing hardcoded.** Every customer-specific value is an env var or Supabase
   row. No hardcoded URLs, tokens, or IPs in the source code.
2. **Customer setup = 5 minutes.** `docker run` with env vars → Supabase project →
   customer downloads app.
3. **Live view deferred.** The API and app UI have placeholder slots, but actual
   MJPEG/WebRTC streaming is not implemented yet.
4. **Telegram for operators, not customers.** The Flutter app is the customer
   interface. Telegram is admin-only debug channel.

## Project Structure

```
codebridge-notifier/
├── AGENTS.md               ← This file. Read first.
├── README.md               ← Customer-facing project overview.
├── backend/
│   ├── Dockerfile          ← Production container image.
│   ├── docker-compose.yml  ← Local dev / self-hosted deployment.
│   ├── requirements.txt    ← Python dependencies.
│   ├── .env.example        ← All configurable env vars with docs.
│   └── src/
│       ├── __init__.py
│       ├── main.py         ← FastAPI app entrypoint + router registration.
│       ├── config.py       ← Pydantic Settings — all env vars.
│       ├── models.py       ← Pydantic response/request schemas.
│       ├── db.py           ← Supabase client wrapper.
│       ├── auth.py         ← Supabase auth verification middleware.
│       ├── routers/
│       │   ├── __init__.py
│       │   ├── cameras.py  ← CRUD for camera configs.
│       │   ├── alerts.py   ← Alert history + snapshot serving.
│       │   └── webhooks.py ← FCM token registration + push.
│       ├── services/
│       │   ├── __init__.py
│       │   ├── detector.py ← YOLO detection loop (thread).
│       │   ├── notifier.py ← Sends pushes (FCM + Telegram).
│       │   └── rtsp.py     ← RTSP stream reader + frame provider.
│       └── utils.py        ─ Redact URLs, helpers.
├── supabase/
│   └── migrations/
│       └── 001_schema.sql  ← Full DB schema (tables, RLS, triggers).
├── flutter_app/
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app.dart
│   │   ├── supabase/
│   │   │   └── client.dart ← Supabase client init.
│   │   ├── auth/
│   │   │   └── auth_service.dart
│   │   ├── models/
│   │   │   ├── camera.dart
│   │   │   └── alert.dart
│   │   ├── screens/
│   │   │   ├── login_screen.dart
│   │   │   ├── camera_list_screen.dart
│   │   │   ├── alert_feed_screen.dart
│   │   │   └── camera_detail_screen.dart  ← Live view placeholder.
│   │   └── widgets/
│   │       ├── camera_card.dart
│   │       └── alert_tile.dart
│   └── pubspec.yaml
├── docs/
│   ├── SETUP.md            ← 5-minute customer deployment guide.
│   ├── ARCHITECTURE.md     ← Full system design doc.
│   └── API.md              ← REST endpoints reference.
└── scripts/
    ├── setup-supabase.sh   ← One-command Supabase project bootstrap.
    └── generate-env.sh     ← Generates .env from template.
```

## Data Flow: Detection → Notification

```
RTSP frame → YOLO detect(person/cat/dog/car)
  └── if match found AND cooldown expired:
       ├── 1. Save snapshot to disk (or Supabase storage)
       ├── 2. Insert alert row into Supabase `alerts` table
       ├── 3. Send FCM push to all registered device tokens
       └── 4. Send Telegram alert (if TELEGRAM_BOT_TOKEN is set)
```

## Supabase Schema (core tables)

- **profiles** — extends `auth.users` with customer-facing fields (name, phone).
- **cameras** — one row per camera per customer (RTSP URL, status, cooldown).
- **alerts** — detection events (camera_id, class, confidence, snapshot_url, seen_at).
- **device_tokens** — FCM tokens for push notifications (user_id, token, platform).

## Current Status

- [x] Architecture documented
- [ ] Backend API — FastAPI scaffold + all endpoints
- [ ] YOLO detection loop
- [ ] Supabase schema + RLS
- [ ] Flutter app — auth + camera list + alerts
- [ ] Docker build + CI
- [ ] Live view (deferred)

## Environment Variables (Backend)

| Variable | Required | Description |
|----------|----------|-------------|
| `SUPABASE_URL` | yes | Supabase project URL |
| `SUPABASE_SERVICE_KEY` | yes | Service role key (server-side) |
| `SUPABASE_ANON_KEY` | yes | Anon key (client-side use) |
| `RTSP_URLS` | yes | Comma-separated RTSP URLs |
| `DETECTION_TARGETS` | no | Comma-separated YOLO classes (default: person,car,cat,dog) |
| `COOLDOWN_SECONDS` | no | Seconds between same-class alerts (default: 60) |
| `CONFIDENCE_THRESHOLD` | no | YOLO confidence 0-1 (default: 0.5) |
| `TELEGRAM_BOT_TOKEN` | no | Telegram bot token for debug alerts |
| `TELEGRAM_CHAT_ID` | no | Chat ID for Telegram debug alerts |
| `FCM_CREDENTIALS` | no | Firebase service account JSON (base64) |
| `LOG_LEVEL` | no | INFO, DEBUG, WARNING (default: INFO) |

## Tips for the Next AI

- The backend uses **asyncio** + **threading** together. YOLO runs in a
  background thread (it's CPU-bound). The FastAPI server runs on the asyncio
  event loop. Use `run_in_executor` for blocking calls.
- Supabase **Realtime** subscriptions are used for the live alert feed in the
  Flutter app (no polling needed).
- Don't store RTSP credentials in the database in plain text — use env vars
  per deployment. The DB stores a camera alias, not the URL.
- FCM uses HTTP v1 API (not legacy). Requires OAuth 2.0 with a Firebase
  service account. The credentials JSON should be base64-encoded in the
  `FCM_CREDENTIALS` env var.
- When adding live view later: serve MJPEG from an endpoint under `/api/stream/`
  proxied through the Cloudflare tunnel. The Flutter app can use the
  `network_image_stream` package or a custom `ImageStream` widget.
- The existing `traffic-camera-phase1` project has the detection logic that
  needs to be ported/reused.
