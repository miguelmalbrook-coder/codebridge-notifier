# Codebridge Notifier

White-label camera monitoring and alert system powered by YOLO object detection.
Get push notifications when people, cars, cats, or dogs appear on your cameras.

**Built by Codebridge Consultancy**

## Quick Start (for customers)

1. Get your credentials from Codebridge.
2. Download the app from the Play Store.
3. Sign in with your email.
4. Approve push notifications.
5. You'll start receiving alerts instantly.

## For Developers

See [SETUP.md](docs/SETUP.md) for deploying a customer instance.
See [ARCHITECTURE.md](docs/ARCHITECTURE.md) for system design.
See [AGENTS.md](AGENTS.md) for the AI agent guide.

## Tech Stack

- **Detection:** YOLO (Ultralytics) on RTSP streams
- **Backend:** Python FastAPI in Docker
- **Database:** Supabase (Postgres + Auth + Realtime)
- **Mobile:** Flutter (Android, iOS-ready)
- **Push:** Firebase Cloud Messaging
- **Debug:** Telegram bot
