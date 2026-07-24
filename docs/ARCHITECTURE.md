# Architecture — Codebridge Notifier

## System Design

```
┌───────────────────────────────────────────────────────┐
│                    Cloudflare Tunnel                    │
│              (optional, for remote API access)          │
└────────────────────────┬──────────────────────────────┘
                         │
┌────────────────────────▼──────────────────────────────┐
│                    Docker Container                     │
│  ┌──────────────────────────────────────────────────┐  │
│  │               FastAPI (uvicorn)                   │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────────────┐  │  │
│  │  │ /api/*   │ │ /api/*   │ │ /api/*           │  │  │
│  │  │ cameras  │ │ alerts   │ │ webhooks         │  │  │
│  │  └────┬─────┘ └────┬─────┘ └───────┬──────────┘  │  │
│  │       │             │              │              │  │
│  │       └─────────────┴──────────────┘              │  │
│  │                    │                              │  │
│  │  ┌─────────────────▼───────────────────────────┐  │  │
│  │  │           Supabase Client (service role)      │  │  │
│  │  └─────────────────┬───────────────────────────┘  │  │
│  └────────────────────┼─────────────────────────────┘  │
│                       │                                │
│  ┌────────────────────▼─────────────────────────────┐  │
│  │         YOLO Detector (background thread)         │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────────────┐  │  │
│  │  │ RTSP     │ │ YOLO     │ │ Cooldown         │  │  │
│  │  │ Reader   │ │ Model    │ │ Gate             │  │  │
│  │  └──────────┘ └──────────┘ └──────────────────┘  │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────┘
         │                      │               │
         ▼                      ▼               ▼
┌──────────────┐    ┌────────────────┐   ┌──────────────┐
│   Supabase   │    │  FCM (Firebase) │   │   Telegram   │
│  (auth + DB) │    │  (push)        │   │  (debug)     │
└──────┬───────┘    └───────┬────────┘   └──────┬───────┘
       │                    │                    │
       ▼                    ▼                    │
┌──────────────┐    ┌──────────────┐            │
│  Flutter App │◄───│ Push Notif   │            │
│  (Android)   │    │  (phone)     │            │
└──────────────┘    └──────────────┘            │
                                               │
                                        ┌──────▼───────┐
                                        │  Telegram    │
                                        │  (admin)     │
                                        └──────────────┘
```

## Data Flow

### Detection Pipeline
1. `RTSPReader` opens connection to camera stream
2. Main loop reads frames in round-robin across cameras
3. `YOLO` model runs inference on each frame
4. Results are checked against configured target classes
5. If match found AND cooldown expired:
   - Snapshot saved to disk
   - Alert row inserted in Supabase `alerts` table
   - FCM push sent to customer devices
   - Telegram alert sent (if configured)

### Auth Flow
1. User logs into Flutter app → Supabase Auth (magic link or email)
2. App receives JWT from Supabase
3. All API calls include `Authorization: Bearer <jwt>`
4. Backend verifies JWT via Supabase Admin API
5. RLS policies enforce per-user data isolation

## Key Decisions

### Why Supabase (not a custom backend DB)?
- Built-in auth with magic links
- Realtime subscriptions (future live feed)
- Row-level security per customer
- No backend DB to maintain

### Why YOLO in a thread (not async)?
- YOLO inference is CPU/GPU-bound, not I/O-bound
- Threading avoids blocking the asyncio event loop
- `run_in_executor` could be used for finer-grained control

### Why FCM (not WebSocket)?
- Push notifications work when app is closed
- Battery-efficient
- Standard on Android

### Why keep Telegram?
- Admin gets system health + critical errors
- Independent of customer app
- Useful during debugging/onboarding

## Future: Live View

Implementation plan (deferred):
1. Add `/api/stream/{camera_id}` endpoint serving MJPEG
2. Proxy through Cloudflare tunnel
3. Flutter app uses `NetworkImage` or custom stream widget
4. Consider WebRTC for lower latency

The camera detail screen has a placeholder tab ready.
