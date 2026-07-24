# Codebridge Notifier — Setup Guide

## Prerequisites

- Docker and Docker Compose (or Podman)
- A Supabase project (free tier works)
- (Optional) A Telegram bot token for debug alerts
- (Optional) A Firebase project for FCM push notifications

## 5-Minute Customer Setup

### 1. Create Supabase Project

1. Go to [supabase.com](https://supabase.com) and create a new project
2. Go to **SQL Editor** and paste + run `supabase/migrations/001_schema.sql`
3. Go to **Authentication → Settings** and enable:
   - Email auth (magic link or password)
   - (Optional) Google OAuth

### 2. Configure Environment

```bash
cp backend/.env.example backend/.env
```

Edit `.env` with your values:

```ini
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_KEY=service_role_key_from_settings
SUPABASE_ANON_KEY=anon_key_from_settings
RTSP_URLS="FrontGate|rtsp://user:pass@192.168.1.10:554/stream1"
TELEGRAM_BOT_TOKEN=your_telegram_bot_token   # optional
TELEGRAM_CHAT_ID=your_chat_id                # optional
FCM_CREDENTIALS=base64_firebase_sa_json      # optional
```

### 3. Start the Backend

```bash
cd backend
docker compose up -d --build
```

The API is now live at `http://localhost:8000`.

### 4. (Optional) Expose via Cloudflare Tunnel

```bash
docker run -d --name cloudflared \
  cloudflare/cloudflared:latest \
  tunnel --url http://host.docker.internal:8000
```

Or use the existing system-dashboard cloudflared setup.

### 5. Flutter App

Build and distribute via:

```bash
cd flutter_app
flutter build apk --release
```

The APK goes to `flutter_app/build/app/outputs/flutter-apk/`.

## Customer Onboarding Flow

1. Codebridge deploys Docker + Supabase project
2. Customer receives:
   - Supabase project URL
   - Login credentials (email + magic link)
   - APK file or Play Store link
3. Customer opens app → signs in → grants notification permission
4. Detection is live — alerts arrive as push notifications

## Updating

```bash
cd backend
git pull
docker compose up -d --build
```

That's it. Database migrations are idempotent (safe to re-run).
