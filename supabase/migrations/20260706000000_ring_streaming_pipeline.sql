-- Continuous ring vitals streaming pipeline: raw per-reading tables pushed every 6h
-- from the local Room DB (native MeasurementLoopManager/SupabaseSyncManager), plus an
-- additive local_reading_id column on the existing per-event tables so the native push
-- can upsert idempotently. Existing daily-aggregate tables (user_hr, user_spo2,
-- user_hrv, user_steps) are untouched — they keep receiving the same upsert shape as
-- before so existing chart/history screens are unaffected.

-- ── New raw-reading tables ──────────────────────────────────────────────────────

create table if not exists public.user_hr_readings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  value_bpm integer not null,
  measured_at timestamptz not null,
  source text not null default 'auto_cycle',
  local_reading_id bigint not null,
  synced_at timestamptz not null default now(),
  unique (user_id, local_reading_id)
);
create index if not exists user_hr_readings_user_measured_idx
  on public.user_hr_readings (user_id, measured_at);

create table if not exists public.user_spo2_readings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  value_pct integer not null,
  measured_at timestamptz not null,
  source text not null default 'auto_cycle',
  local_reading_id bigint not null,
  synced_at timestamptz not null default now(),
  unique (user_id, local_reading_id)
);
create index if not exists user_spo2_readings_user_measured_idx
  on public.user_spo2_readings (user_id, measured_at);

create table if not exists public.user_hrv_readings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  value_ms integer not null,
  measured_at timestamptz not null,
  source text not null default 'auto_cycle',
  local_reading_id bigint not null,
  synced_at timestamptz not null default now(),
  unique (user_id, local_reading_id)
);
create index if not exists user_hrv_readings_user_measured_idx
  on public.user_hrv_readings (user_id, measured_at);

create table if not exists public.user_steps_snapshots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  steps integer not null,
  calories_kcal integer not null,
  distance_m numeric not null,
  captured_at timestamptz not null,
  source text not null default 'auto_cycle',
  local_reading_id bigint not null,
  synced_at timestamptz not null default now(),
  unique (user_id, local_reading_id)
);
create index if not exists user_steps_snapshots_user_captured_idx
  on public.user_steps_snapshots (user_id, captured_at);

alter table public.user_hr_readings enable row level security;
alter table public.user_spo2_readings enable row level security;
alter table public.user_hrv_readings enable row level security;
alter table public.user_steps_snapshots enable row level security;

create policy "user_hr_readings_owner" on public.user_hr_readings
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "user_spo2_readings_owner" on public.user_spo2_readings
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "user_hrv_readings_owner" on public.user_hrv_readings
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "user_steps_snapshots_owner" on public.user_steps_snapshots
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ── Additive column on EXISTING per-event tables (non-breaking) ────────────────
-- Existing manual "Measure Now" inserts (user_bp/user_stress/user_temp) leave this
-- column null and are completely unaffected; only the native SupabaseSyncManager's
-- push sets it, relying on the partial unique index below for idempotent retries.

alter table public.user_bp add column if not exists local_reading_id bigint;
alter table public.user_stress add column if not exists local_reading_id bigint;
alter table public.user_temp add column if not exists local_reading_id bigint;

create unique index if not exists user_bp_local_reading_idx
  on public.user_bp (user_id, local_reading_id) where local_reading_id is not null;
create unique index if not exists user_stress_local_reading_idx
  on public.user_stress (user_id, local_reading_id) where local_reading_id is not null;
create unique index if not exists user_temp_local_reading_idx
  on public.user_temp (user_id, local_reading_id) where local_reading_id is not null;
