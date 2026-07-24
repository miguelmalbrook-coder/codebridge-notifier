#!/usr/bin/env bash
# Generates .env from template for a new customer deployment.
# Usage: ./scripts/generate-env.sh

set -Eeuo pipefail

ENV_FILE="backend/.env"
EXAMPLE_FILE="backend/.env.example"

if [[ ! -f "$EXAMPLE_FILE" ]]; then
  echo "ERROR: $EXAMPLE_FILE not found. Run from project root."
  exit 1
fi

cp "$EXAMPLE_FILE" "$ENV_FILE"
echo "✅ Created $ENV_FILE from template"
echo ""
echo "Now edit $ENV_FILE with your values:"
echo "  - SUPABASE_URL"
echo "  - SUPABASE_SERVICE_KEY"
echo "  - SUPABASE_ANON_KEY"
echo "  - RTSP_URLS"
echo "  - (optional) TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID"
echo "  - (optional) FCM_CREDENTIALS"
