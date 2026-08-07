-- 20260806000000_missing_tables.sql
-- Creates every table the app reads/writes that earlier migrations never created.
-- The app (Dart supabase_service + Kotlin SupabaseSyncManager + prayer screens) hits
-- all of these; fresh environments were silently losing every vitals row.
--
-- Idempotent: CREATE TABLE IF NOT EXISTS + guarded ALTERs, so this is safe to run on a
-- live DB where some tables (user_bp/user_stress/user_temp) already exist manually.

-- ── Profile ──────────────────────────────────────────────────────────────────

create table if not exists public.user_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  age integer,
  gender text,
  height_cm integer,
  weight_kg numeric,
  address text,
  additional_instructions text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ── Daily aggregate vitals (Dart upsert shape, keyed user_id+date) ───────────

create table if not exists public.user_steps (
  user_id uuid not null references auth.users(id) on delete cascade,
  date date not null,
  steps integer not null,
  calories integer not null,
  distance_m numeric not null,
  synced_at timestamptz not null default now(),
  unique (user_id, date)
);

create table if not exists public.user_hr (
  user_id uuid not null references auth.users(id) on delete cascade,
  date date not null,
  avg_hr integer not null,
  min_hr integer not null,
  max_hr integer not null,
  sample_count integer not null default 0,
  synced_at timestamptz not null default now(),
  unique (user_id, date)
);

create table if not exists public.user_spo2 (
  user_id uuid not null references auth.users(id) on delete cascade,
  date date not null,
  avg_spo2 integer not null,
  min_spo2 integer not null,
  max_spo2 integer not null,
  sample_count integer not null default 0,
  synced_at timestamptz not null default now(),
  unique (user_id, date)
);

create table if not exists public.user_hrv (
  user_id uuid not null references auth.users(id) on delete cascade,
  date date not null,
  avg_hrv integer not null,
  min_hrv integer not null,
  max_hrv integer not null,
  sample_count integer not null default 0,
  synced_at timestamptz not null default now(),
  unique (user_id, date)
);

-- ── Per-event vitals (manual inserts + native sync; local_reading_id mirrors the
--    additive columns the ring-streaming migration expects to exist) ──────────

create table if not exists public.user_bp (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  systolic integer not null,
  diastolic integer not null,
  measured_at timestamptz not null,
  source text not null default 'manual',
  local_reading_id bigint,
  synced_at timestamptz not null default now()
);

create table if not exists public.user_stress (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  stress_value integer not null,
  label text,
  measured_at timestamptz not null,
  source text not null default 'manual',
  local_reading_id bigint,
  synced_at timestamptz not null default now()
);

create table if not exists public.user_temp (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  value_c numeric not null,
  measured_at timestamptz not null,
  source text not null default 'auto',
  local_reading_id bigint,
  synced_at timestamptz not null default now()
  -- (user_id, measured_at) unique is added by 20260807000000_fix_delete_user_account.sql
  -- so fresh and live DBs end up with the same constraint name.
);

-- Native sync upserts against (user_id, measured_at); Dart temp upserts use the
-- same conflict target. Safe no-ops when the tables pre-existed.
alter table public.user_bp add column if not exists local_reading_id bigint;
alter table public.user_stress add column if not exists local_reading_id bigint;
alter table public.user_temp add column if not exists local_reading_id bigint;

create unique index if not exists user_bp_local_reading_idx
  on public.user_bp (user_id, local_reading_id) where local_reading_id is not null;
create unique index if not exists user_stress_local_reading_idx
  on public.user_stress (user_id, local_reading_id) where local_reading_id is not null;
create unique index if not exists user_temp_local_reading_idx
  on public.user_temp (user_id, local_reading_id) where local_reading_id is not null;

create index if not exists user_bp_user_measured_idx
  on public.user_bp (user_id, measured_at);
create index if not exists user_stress_user_measured_idx
  on public.user_stress (user_id, measured_at);

-- ── Workouts (ring workouts) ─────────────────────────────────────────────────

create table if not exists public.user_workouts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  workout_type text not null,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  duration_s integer not null default 0,
  steps integer not null default 0,
  calories integer not null default 0,
  distance_m numeric not null default 0,
  avg_hr integer,
  avg_spo2 integer,
  avg_bp_sbp integer,
  avg_bp_dbp integer,
  created_at timestamptz not null default now()
);
create index if not exists user_workouts_user_started_idx
  on public.user_workouts (user_id, started_at desc);

-- ── Sleep ────────────────────────────────────────────────────────────────────

create table if not exists public.user_sleep (
  user_id uuid not null references auth.users(id) on delete cascade,
  date date not null,
  total_duration integer not null default 0,
  deep_duration integer not null default 0,
  light_duration integer not null default 0,
  rem_duration integer not null default 0,
  awake_duration integer not null default 0,
  sleep_score integer not null default 0,
  sleep_time integer not null default 0,
  wake_time integer not null default 0,
  synced_at timestamptz not null default now(),
  unique (user_id, date)
);

-- ── Women's health ───────────────────────────────────────────────────────────

create table if not exists public.user_cycles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  period_start date not null,
  cycle_length integer not null default 28,
  period_length integer not null default 5,
  notes text,
  created_at timestamptz not null default now(),
  unique (user_id, period_start)
);

create table if not exists public.user_symptoms (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  logged_date date not null,
  mood text,
  energy integer,
  cramps boolean not null default false,
  headache boolean not null default false,
  bloating boolean not null default false,
  notes text,
  created_at timestamptz not null default now(),
  unique (user_id, logged_date)
);

-- ── Emergency contacts (cloud mirror of the native Room table) ──────────────

create table if not exists public.user_emergency_contacts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  local_id integer not null,
  name text not null,
  phone text not null,
  created_at timestamptz not null default now(),
  unique (user_id, local_id)
);

-- ── Prayer sessions (workout_type = 'Prayer') ────────────────────────────────

create table if not exists public.workouts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  workout_type text not null,
  duration_seconds integer not null default 0,
  avg_heart_rate integer,
  avg_hrv integer,
  calmness_score integer,
  rating integer,
  created_at timestamptz not null default now()
);
create index if not exists workouts_user_created_idx
  on public.workouts (user_id, created_at desc);

-- ── Row Level Security ───────────────────────────────────────────────────────

alter table public.user_profiles enable row level security;
alter table public.user_steps enable row level security;
alter table public.user_hr enable row level security;
alter table public.user_spo2 enable row level security;
alter table public.user_hrv enable row level security;
alter table public.user_bp enable row level security;
alter table public.user_stress enable row level security;
alter table public.user_temp enable row level security;
alter table public.user_workouts enable row level security;
alter table public.user_sleep enable row level security;
alter table public.user_cycles enable row level security;
alter table public.user_symptoms enable row level security;
alter table public.user_emergency_contacts enable row level security;
alter table public.workouts enable row level security;

-- Owner policies, guarded so re-runs / pre-existing tables with policies don't fail.
do $$
begin
  if not exists (select 1 from pg_policy where polrelid = 'public.user_profiles'::regclass and polname = 'user_profiles_owner') then
    create policy "user_profiles_owner" on public.user_profiles
      for all using (auth.uid() = id) with check (auth.uid() = id);
  end if;
end $$;

do $$
declare
  t text;
begin
  foreach t in array array[
    'user_steps','user_hr','user_spo2','user_hrv','user_bp','user_stress',
    'user_temp','user_workouts','user_sleep','user_cycles','user_symptoms',
    'user_emergency_contacts','workouts'
  ]
  loop
    if not exists (
      select 1 from pg_policy
      where polrelid = format('public.%I', t)::regclass and polname = t || '_owner'
    ) then
      execute format(
        'create policy %I on public.%I for all using (auth.uid() = user_id) with check (auth.uid() = user_id)',
        t || '_owner', t
      );
    end if;
  end loop;
end $$;

-- ── Account deletion: also wipe prayer workouts (recreate the RPC; earlier
--    migration predates this table) ──────────────────────────────────────────

create or replace function public.delete_user_account()
returns void
language plpgsql
security definer
as $$
declare
  current_user_id uuid;
begin
  current_user_id := auth.uid();

  if current_user_id is null then
    raise exception 'Not authenticated';
  end if;

  delete from public.messages where conversation_id in (select id from public.conversations where user_id = current_user_id);

  delete from public.conversations where user_id = current_user_id;
  delete from public.vital_readings where user_id = current_user_id;
  delete from public.sedentary_alerts where user_id = current_user_id;
  delete from public.workout_analytics where user_id = current_user_id;
  delete from public.sleep_sessions where user_id = current_user_id;
  delete from public.ring_sync_cache where user_id = current_user_id;
  delete from public.activity_goals where user_id = current_user_id;
  delete from public.sedentary_logs where user_id = current_user_id;
  delete from public.workout_sessions where user_id = current_user_id;
  delete from public.medical_events where user_id = current_user_id;
  delete from public.medications where user_id = current_user_id;
  delete from public.lab_reports where user_id = current_user_id;
  delete from public.user_blood_panels where user_id = current_user_id;

  delete from public.user_profiles where id = current_user_id;
  delete from public.user_bp where user_id = current_user_id;
  delete from public.user_stress where user_id = current_user_id;
  delete from public.user_temp where user_id = current_user_id;
  delete from public.user_workouts where user_id = current_user_id;
  delete from public.user_sleep where user_id = current_user_id;
  delete from public.user_cycles where user_id = current_user_id;
  delete from public.user_symptoms where user_id = current_user_id;
  delete from public.user_emergency_contacts where user_id = current_user_id;
  delete from public.user_steps where user_id = current_user_id;
  delete from public.user_hr where user_id = current_user_id;
  delete from public.user_spo2 where user_id = current_user_id;
  delete from public.user_hrv where user_id = current_user_id;
  delete from public.user_hr_readings where user_id = current_user_id;
  delete from public.user_spo2_readings where user_id = current_user_id;
  delete from public.user_hrv_readings where user_id = current_user_id;
  delete from public.user_steps_snapshots where user_id = current_user_id;
  delete from public.workouts where user_id = current_user_id;

  delete from auth.users where id = current_user_id;
end;
$$;
