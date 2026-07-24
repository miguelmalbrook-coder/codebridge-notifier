-- Codebridge Notifier — Supabase Schema
-- Run this in your Supabase SQL editor to bootstrap the project.

-- 0. Extensions
create extension if not exists "pgcrypto";

-- 1. Profiles (extends auth.users)
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  name        text not null default '',
  phone       text not null default '',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- Auto-create profile on user signup
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, name, phone)
  values (new.id, '', '');
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 2. Cameras
create table if not exists public.cameras (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  alias       text not null default 'Camera',
  status      text not null default 'offline'
              check (status in ('online', 'offline', 'error')),
  rtsp_url    text not null default '',
  cooldown_sec int not null default 60,
  created_at  timestamptz not null default now(),
  last_seen   timestamptz
);

-- 3. Alerts (detection events)
create table if not exists public.alerts (
  id            uuid primary key default gen_random_uuid(),
  camera_id     text not null,        -- camera alias from config
  class_name    text not null,
  confidence    real not null default 0.0,
  snapshot_url  text not null default '',
  seen_at       timestamptz not null default now(),
  created_at    timestamptz not null default now()
);

-- 4. Device tokens (FCM push)
create table if not exists public.device_tokens (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  token       text not null unique,
  platform    text not null default 'android'
              check (platform in ('android', 'ios', 'web')),
  created_at  timestamptz not null default now()
);

-- Indexes
create index if not exists idx_alerts_seen_at on public.alerts(seen_at desc);
create index if not exists idx_alerts_camera on public.alerts(camera_id);
create index if not exists idx_cameras_user on public.cameras(user_id);
create index if not exists idx_device_tokens_user on public.device_tokens(user_id);

-- 5. Row-Level Security (RLS)
-- Customers can only see their own data.

alter table public.profiles enable row level security;
alter table public.cameras enable row level security;
alter table public.alerts enable row level security;
alter table public.device_tokens enable row level security;

-- Profiles: users can read/update their own
create policy "Users can read own profile"
  on public.profiles for select
  using (auth.uid() = id);

create policy "Users can update own profile"
  on public.profiles for update
  using (auth.uid() = id);

-- Cameras: users can CRUD their own
create policy "Users can read own cameras"
  on public.cameras for select
  using (auth.uid() = user_id);

create policy "Users can insert own cameras"
  on public.cameras for insert
  with check (auth.uid() = user_id);

create policy "Users can update own cameras"
  on public.cameras for update
  using (auth.uid() = user_id);

create policy "Users can delete own cameras"
  on public.cameras for delete
  using (auth.uid() = user_id);

-- Alerts: users can read alerts for their cameras
-- (camera_id is a text alias; access is granted via the camera owner)
create policy "Users can read alerts for own cameras"
  on public.alerts for select
  using (
    exists (
      select 1 from public.cameras
      where cameras.alias = alerts.camera_id
      and cameras.user_id = auth.uid()
    )
  );

-- Device tokens: users can manage their own
create policy "Users can read own device tokens"
  on public.device_tokens for select
  using (auth.uid() = user_id);

create policy "Users can insert own device tokens"
  on public.device_tokens for insert
  with check (auth.uid() = user_id);

create policy "Users can delete own device tokens"
  on public.device_tokens for delete
  using (auth.uid() = user_id);

-- Service role bypasses RLS (used by backend).
