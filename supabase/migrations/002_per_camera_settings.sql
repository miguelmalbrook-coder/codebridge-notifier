-- Add per-camera detection settings
-- Run this in Supabase SQL Editor (Dashboard → SQL Editor → New query)

ALTER TABLE cameras ADD COLUMN IF NOT EXISTS detection_mode text DEFAULT 'yolo';
ALTER TABLE cameras ADD COLUMN IF NOT EXISTS model text DEFAULT 'yolo11s.pt';
ALTER TABLE cameras ADD COLUMN IF NOT EXISTS confidence numeric DEFAULT 0.4;
ALTER TABLE cameras ADD COLUMN IF NOT EXISTS cooldown_seconds integer DEFAULT 15;
ALTER TABLE cameras ADD COLUMN IF NOT EXISTS targets text[] DEFAULT '{person,car,cat,dog}';
