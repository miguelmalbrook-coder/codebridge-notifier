#!/usr/bin/env bash
# One-command Supabase project bootstrap.
# Usage: ./scripts/setup-supabase.sh <supabase-project-ref>

set -Eeuo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <supabase-project-ref>"
  echo "  (find your project ref in Supabase dashboard → Settings → General)"
  exit 1
fi

PROJECT_REF="$1"
SQL_FILE="supabase/migrations/001_schema.sql"

if [[ ! -f "$SQL_FILE" ]]; then
  echo "ERROR: $SQL_FILE not found. Run this from the project root."
  exit 1
fi

echo "=== Codebridge Notifier — Supabase Setup ==="
echo "Project ref: $PROJECT_REF"
echo ""

# Option 1: Use Supabase CLI
if command -v supabase &>/dev/null; then
  echo "Using Supabase CLI..."
  supabase link --project-ref "$PROJECT_REF"
  supabase db push
  echo "✅ Schema applied via Supabase CLI"
  exit 0
fi

# Option 2: Manual instruction
echo ""
echo "Supabase CLI not found. Manual steps:"
echo ""
echo "  1. Go to https://supabase.com/dashboard/project/$PROJECT_REF"
echo "  2. Open SQL Editor"
echo "  3. Paste the contents of $SQL_FILE"
echo "  4. Click Run"
echo ""
echo "  SQL file contents shown below (first 20 lines):"
echo ""
head -20 "$SQL_FILE"
