ALTER TABLE cameras ADD COLUMN IF NOT EXISTS class_confidences jsonb DEFAULT '{}'::jsonb;
