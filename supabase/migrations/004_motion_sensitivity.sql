ALTER TABLE cameras ADD COLUMN IF NOT EXISTS motion_sensitivity numeric DEFAULT 0.001;
