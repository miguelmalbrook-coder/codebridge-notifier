# Codebridge Notifier — API Reference

Base URL: `http://your-backend:8000` (or tunnel URL)

## Authentication

All endpoints except `/api/health`, `/api/config`, `/api/docs` require a
Supabase JWT in the `Authorization` header:

```
Authorization: Bearer <supabase_jwt_token>
```

Get a token via Supabase Auth (magic link, email/password, or Google OAuth).

## Endpoints

### GET /api/health

Public. Returns backend status.

```json
{"status": "ok", "cameras": 2, "uptime": 3600.0, "version": "0.1.0"}
```

### GET /api/config

Public. Returns dynamic config (tunnel URL, version).

```json
{"tunnel_url": "", "version": "0.1.0"}
```

### GET /api/cameras

Auth required. Returns all cameras for the authenticated user.

```json
[
  {
    "id": "uuid",
    "alias": "FrontGate",
    "status": "online",
    "last_seen": "2026-07-24T10:00:00Z",
    "created_at": "2026-07-24T09:00:00Z"
  }
]
```

### GET /api/cameras/{id}

Auth required. Get a single camera.

### PATCH /api/cameras/{id}

Auth required. Update camera fields (alias, status).

```json
{"alias": "Side Gate"}
```

### GET /api/alerts

Auth required. Paginated alert history.

Query params:
- `page` (default: 1)
- `per_page` (default: 20, max: 100)
- `camera_id` (optional filter)

```json
{
  "alerts": [
    {
      "id": "uuid",
      "camera_id": "FrontGate",
      "camera_alias": "",
      "class_name": "person",
      "confidence": 0.87,
      "snapshot_url": "/snapshots/FrontGate/person_20260724_100000.jpg",
      "seen_at": "2026-07-24T10:00:00Z"
    }
  ],
  "total": 42,
  "page": 1,
  "per_page": 20
}
```

### GET /api/alerts/{id}

Auth required. Get a single alert.

### POST /api/devices/register

Auth required. Register device FCM token for push notifications.

```json
{"token": "fcm_token_here", "platform": "android"}
```

Response: `{"success": true, "message": "Device registered"}`

### POST /api/devices/unregister

Auth required. Remove device FCM token.

```json
{"token": "fcm_token_here", "platform": "android"}
```

Response: `{"success": true, "message": "Device unregistered"}`
