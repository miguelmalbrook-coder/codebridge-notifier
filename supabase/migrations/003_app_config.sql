-- Run this in Supabase Dashboard → SQL Editor → New query
CREATE TABLE IF NOT EXISTS app_config (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tunnel_url text DEFAULT '',
  subscribed boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

-- Insert default row (skip if already exists)
INSERT INTO app_config (tunnel_url, subscribed)
VALUES ('https://writers-positive-submissions-miracle.trycloudflare.com', true)
ON CONFLICT DO NOTHING;
