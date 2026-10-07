-- 00000000000000_init.sql
--
-- SUNDR Vital Monitoring — single fresh-database init.
-- Squashed 2026-09-18 from 14 incremental migrations into one file that
-- creates the FINAL schema state directly (no intermediate constraint swaps
-- or superseded function versions). Fully idempotent: every object uses
-- IF NOT EXISTS / guarded DO blocks, so it is safe to run on the live DB
-- to converge it, or on an empty project to initialise it.
--
-- Covers: profile, daily vitals, per-event vitals, workouts, sleep, women's
-- health, emergency contacts, raw ring streaming, incidents, firmware OTA,
-- emergency alerting, ECG/breath/sugar, social/quran/nutrition/watchface,
-- health engine config, falls, derived cycles view, RLS + grants.

-- ── Extensions ───────────────────────────────────────────────────────────

create extension if not exists "pgcrypto";

-- ── Profile ──────────────────────────────────────────────────────────────

create table if not exists public.user_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  age integer,
  gender text,
  height_cm integer,
  weight_kg numeric,
  address text,
  phone text,
  additional_instructions text,
  default_emergency_contact text default '101',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ── Daily aggregate vitals (Dart upsert shape, keyed user_id+date) ────────

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

-- ── Per-event vitals (final state: local_reading_id for native traceability,
--    partial unique index for idempotent native retries, full unique
--    (user_id, measured_at) for PostgREST on_conflict pushes) ─────────────

create table if not exists public.user_bp (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  systolic integer not null,
  diastolic integer not null,
  measured_at timestamptz not null,
  source text not null default 'manual',
  local_reading_id bigint,
  synced_at timestamptz not null default now(),
  unique (user_id, measured_at)
);

create table if not exists public.user_stress (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  stress_value integer not null,
  label text,
  measured_at timestamptz not null,
  source text not null default 'manual',
  local_reading_id bigint,
  synced_at timestamptz not null default now(),
  unique (user_id, measured_at)
);

create table if not exists public.user_temp (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  value_c numeric not null,
  measured_at timestamptz not null,
  source text not null default 'auto',
  local_reading_id bigint,
  synced_at timestamptz not null default now(),
  unique (user_id, measured_at)
);

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

-- ── Workouts ─────────────────────────────────────────────────────────────

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
  locations jsonb,
  created_at timestamptz not null default now()
);
create index if not exists user_workouts_user_started_idx
  on public.user_workouts (user_id, started_at desc);

-- Prayer sessions (workout_type = 'Prayer')

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

-- ── Sleep ────────────────────────────────────────────────────────────────

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

-- ── Women's health ───────────────────────────────────────────────────────

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
  flow_intensity text,
  flow_color text,
  notes text,
  created_at timestamptz not null default now(),
  unique (user_id, logged_date)
);

-- ── Assist chat history (written by the MedXAI API, not the app client) ──

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists conversations_user_created_idx
  on public.conversations (user_id, created_at desc);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  role text not null,
  content text not null,
  card jsonb,
  created_at timestamptz not null default now()
);
create index if not exists messages_conversation_created_idx
  on public.messages (conversation_id, created_at);

-- ── Emergency contacts (cloud mirror of the native Room table) ───────────

create table if not exists public.user_emergency_contacts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  local_id integer not null,
  name text not null,
  phone text not null,
  created_at timestamptz not null default now(),
  unique (user_id, local_id)
);

-- ── Raw ring streaming (native SupabaseSyncManager, final constraints) ───

create table if not exists public.user_hr_readings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  value_bpm integer not null,
  measured_at timestamptz not null,
  source text not null default 'auto_cycle',
  local_reading_id bigint not null,
  synced_at timestamptz not null default now(),
  unique (user_id, measured_at)
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
  unique (user_id, measured_at)
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
  unique (user_id, measured_at)
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
  unique (user_id, captured_at)
);
create index if not exists user_steps_snapshots_user_captured_idx
  on public.user_steps_snapshots (user_id, captured_at);

-- ── App incidents ────────────────────────────────────────────────────────

create table if not exists public.app_incidents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  source text not null,
  error_type text,
  message text not null,
  stack_trace text,
  device_info jsonb default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists idx_app_incidents_created_at
  on public.app_incidents(created_at desc);
create index if not exists idx_app_incidents_source
  on public.app_incidents(source);
create index if not exists idx_app_incidents_user_id
  on public.app_incidents(user_id);

-- ── Firmware OTA ─────────────────────────────────────────────────────────

create table if not exists public.firmware_updates (
  id uuid primary key default gen_random_uuid(),
  version text not null,
  hardware_model text default 'QRing V1',
  file_url text not null,
  release_notes text,
  is_mandatory boolean default false,
  created_at timestamptz default now()
);

-- ── Emergency alerting + push tokens ─────────────────────────────────────

create table if not exists public.user_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  fcm_token text not null,
  platform text not null default 'android',
  updated_at timestamptz not null default now(),
  unique (user_id, fcm_token)
);
create index if not exists user_push_tokens_user_idx
  on public.user_push_tokens (user_id);

create table if not exists public.caregiver_link_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users(id) on delete cascade,
  target_user_id uuid not null references auth.users(id) on delete cascade,
  contact_name text not null default '',
  contact_phone text not null,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'declined', 'canceled')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  unique (requester_id, target_user_id, contact_phone)
);
create index if not exists caregiver_link_requests_target_idx
  on public.caregiver_link_requests (target_user_id, status);

create table if not exists public.caregiver_links (
  id uuid primary key default gen_random_uuid(),
  wearer_user_id uuid not null references auth.users(id) on delete cascade,
  caregiver_user_id uuid not null references auth.users(id) on delete cascade,
  contact_name text not null default '',
  contact_phone text not null,
  created_at timestamptz not null default now(),
  unique (wearer_user_id, caregiver_user_id)
);
create index if not exists caregiver_links_caregiver_idx
  on public.caregiver_links (caregiver_user_id);

create table if not exists public.emergency_alerts (
  id uuid primary key default gen_random_uuid(),
  wearer_user_id uuid not null references auth.users(id) on delete cascade,
  reason text not null default 'fall',
  message text not null default '',
  location_lat double precision,
  location_lng double precision,
  location_accuracy_m double precision,
  triggered_by text not null default 'device'
    check (triggered_by in ('device', 'manual', 'cloud_fallback')),
  triggered_at timestamptz not null default now()
);
create index if not exists emergency_alerts_wearer_time_idx
  on public.emergency_alerts (wearer_user_id, triggered_at desc);

create table if not exists public.emergency_alert_deliveries (
  id uuid primary key default gen_random_uuid(),
  alert_id uuid not null references public.emergency_alerts(id) on delete cascade,
  caregiver_user_id uuid references auth.users(id) on delete set null,
  contact_name text not null default '',
  contact_phone text not null,
  channel text not null check (channel in ('device_sms', 'cloud_sms', 'fcm_push')),
  status text not null default 'queued'
    check (status in ('queued', 'sent', 'delivered', 'failed', 'skipped')),
  detail text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists emergency_alert_deliveries_alert_idx
  on public.emergency_alert_deliveries (alert_id);

-- ── ECG / breath / blood sugar ───────────────────────────────────────────

create table if not exists public.user_ecg (
  user_id uuid not null references auth.users(id) on delete cascade,
  measured_at timestamptz not null,
  avg_heart int not null default 0,
  data_list jsonb not null default '[]'::jsonb,
  type int not null default 0,
  created_at timestamptz not null default now(),
  primary key (user_id, measured_at)
);

create table if not exists public.user_breath_sessions (
  user_id uuid not null references auth.users(id) on delete cascade,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  duration_s int not null,
  method_id text not null,
  average_hr int,
  subjective_feeling int,
  created_at timestamptz not null default now(),
  primary key (user_id, started_at)
);

create table if not exists public.user_blood_sugar (
  user_id uuid not null references auth.users(id) on delete cascade,
  measured_at timestamptz not null,
  min_sugar int not null,
  max_sugar int not null,
  hour int not null,
  created_at timestamptz not null default now(),
  primary key (user_id, measured_at)
);

-- ── Social / Quran / nutrition / watchface ───────────────────────────────

create table if not exists public.user_quran_bookmarks (
  user_id uuid not null references auth.users(id) on delete cascade,
  chapter_index int not null,
  is_collection boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (user_id, chapter_index)
);

create table if not exists public.user_friends (
  user_id uuid not null references auth.users(id) on delete cascade,
  friend_user_id text not null,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  primary key (user_id, friend_user_id)
);

create table if not exists public.user_nutrition_logs (
  user_id uuid not null references auth.users(id) on delete cascade,
  date date not null,
  calories int not null,
  carbs int not null default 0,
  protein int not null default 0,
  fat int not null default 0,
  created_at timestamptz not null default now(),
  primary key (user_id, date)
);

create table if not exists public.user_watchface (
  user_id uuid not null references auth.users(id) on delete cascade,
  installed_name text not null,
  installed_at timestamptz not null default now(),
  primary key (user_id)
);

-- ── Health engine config (singleton row deep-merged over app defaults) ───

create table if not exists public.health_engine_config (
  id int primary key,
  config jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

insert into public.health_engine_config (id, config)
values (1, '{}'::jsonb)
on conflict (id) do nothing;

create or replace function public.touch_health_engine_config()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_touch_health_engine_config on public.health_engine_config;
create trigger trg_touch_health_engine_config
  before update on public.health_engine_config
  for each row execute function public.touch_health_engine_config();

-- ── Falls ────────────────────────────────────────────────────────────────

create table if not exists public.falls (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  timestamp timestamptz not null,
  severity double precision not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists falls_user_time_idx
  on public.falls (user_id, timestamp desc);

-- ── Derived cycles view (period runs from consecutive flow-marked days) ──

drop view if exists public.derived_user_cycles;
create view public.derived_user_cycles
with (security_invoker = true) as
with flow_days as (
  select
    user_id,
    logged_date as d,
    notes,
    logged_date - (row_number() over (
      partition by user_id order by logged_date
    ))::int as grp
  from public.user_symptoms
  where flow_intensity is not null
),
runs as (
  select
    user_id,
    min(d) as period_start,
    count(*)::int as period_length,
    (array_agg(notes order by d))[1] as notes
  from flow_days
  group by user_id, grp
),
with_next as (
  select
    user_id,
    period_start,
    period_length,
    notes,
    lead(period_start) over (
      partition by user_id order by period_start
    ) as next_start
  from runs
)
select
  user_id,
  period_start,
  coalesce((next_start - period_start), 28) as cycle_length,
  period_length,
  notes
from with_next;

-- ── Row Level Security ───────────────────────────────────────────────────

alter table public.user_profiles enable row level security;
alter table public.user_steps enable row level security;
alter table public.user_hr enable row level security;
alter table public.user_spo2 enable row level security;
alter table public.user_hrv enable row level security;
alter table public.user_bp enable row level security;
alter table public.user_stress enable row level security;
alter table public.user_temp enable row level security;
alter table public.user_workouts enable row level security;
alter table public.workouts enable row level security;
alter table public.user_sleep enable row level security;
alter table public.user_cycles enable row level security;
alter table public.user_symptoms enable row level security;
alter table public.user_emergency_contacts enable row level security;
alter table public.user_hr_readings enable row level security;
alter table public.user_spo2_readings enable row level security;
alter table public.user_hrv_readings enable row level security;
alter table public.user_steps_snapshots enable row level security;
alter table public.app_incidents enable row level security;
alter table public.firmware_updates enable row level security;
alter table public.user_push_tokens enable row level security;
alter table public.caregiver_link_requests enable row level security;
alter table public.caregiver_links enable row level security;
alter table public.emergency_alerts enable row level security;
alter table public.emergency_alert_deliveries enable row level security;
alter table public.user_ecg enable row level security;
alter table public.user_breath_sessions enable row level security;
alter table public.user_blood_sugar enable row level security;
alter table public.user_quran_bookmarks enable row level security;
alter table public.user_friends enable row level security;
alter table public.user_nutrition_logs enable row level security;
alter table public.user_watchface enable row level security;
alter table public.health_engine_config enable row level security;
alter table public.falls enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;

-- Owner policies (one DO block per table group keeps re-runs safe).

do $$ begin
  if not exists (select 1 from pg_policy where polrelid = 'public.user_profiles'::regclass and polname = 'user_profiles_owner') then
    create policy "user_profiles_owner" on public.user_profiles
      for all using (auth.uid() = id) with check (auth.uid() = id);
  end if;
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'user_steps','user_hr','user_spo2','user_hrv','user_bp','user_stress',
    'user_temp','user_workouts','user_sleep','user_cycles','user_symptoms',
    'user_emergency_contacts','workouts','user_hr_readings','user_spo2_readings',
    'user_hrv_readings','user_steps_snapshots','user_ecg','user_breath_sessions',
    'user_blood_sugar','user_quran_bookmarks','user_friends','user_nutrition_logs',
    'user_watchface','falls','user_push_tokens','conversations'
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

do $$ begin
  if to_regclass('public.messages') is not null
     and not exists (
       select 1 from pg_policy
       where polrelid = 'public.messages'::regclass and polname = 'messages_own'
     ) then
    create policy messages_own on public.messages
      for all to authenticated
      using (
        exists (
          select 1 from public.conversations c
          where c.id = conversation_id and c.user_id = auth.uid()
        )
      )
      with check (
        exists (
          select 1 from public.conversations c
          where c.id = conversation_id and c.user_id = auth.uid()
        )
      );
  end if;
end $$;

-- Policy names differ from the <table>_owner convention for these tables,
-- so they are created explicitly (phase-2/3 originals).

do $$ begin
  if not exists (select 1 from pg_policy where polrelid = 'public.user_ecg'::regclass and polname = 'owner can manage user_ecg') then
    create policy "owner can manage user_ecg" on public.user_ecg for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
  end if;
  if not exists (select 1 from pg_policy where polrelid = 'public.user_breath_sessions'::regclass and polname = 'owner can manage user_breath_sessions') then
    create policy "owner can manage user_breath_sessions" on public.user_breath_sessions for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
  end if;
  if not exists (select 1 from pg_policy where polrelid = 'public.user_blood_sugar'::regclass and polname = 'owner can manage user_blood_sugar') then
    create policy "owner can manage user_blood_sugar" on public.user_blood_sugar for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
  end if;
  if not exists (select 1 from pg_policy where polrelid = 'public.user_quran_bookmarks'::regclass and polname = 'owner can manage quran') then
    create policy "owner can manage quran" on public.user_quran_bookmarks for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
  end if;
  if not exists (select 1 from pg_policy where polrelid = 'public.user_friends'::regclass and polname = 'owner can manage friends') then
    create policy "owner can manage friends" on public.user_friends for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
  end if;
  if not exists (select 1 from pg_policy where polrelid = 'public.user_nutrition_logs'::regclass and polname = 'owner can manage nutrition') then
    create policy "owner can manage nutrition" on public.user_nutrition_logs for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
  end if;
  if not exists (select 1 from pg_policy where polrelid = 'public.user_watchface'::regclass and polname = 'owner can manage watchface') then
    create policy "owner can manage watchface" on public.user_watchface for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
  end if;
end $$;

-- Incidents: anon + authenticated insert, service_role full.

do $$ begin
  if not exists (select 1 from pg_policy where polrelid = 'public.app_incidents'::regclass and polname = 'Allow authenticated insert into app_incidents') then
    create policy "Allow authenticated insert into app_incidents" on public.app_incidents
      for insert to authenticated with check (true);
  end if;
  if not exists (select 1 from pg_policy where polrelid = 'public.app_incidents'::regclass and polname = 'Allow anon insert into app_incidents') then
    create policy "Allow anon insert into app_incidents" on public.app_incidents
      for insert to anon with check (true);
  end if;
  if not exists (select 1 from pg_policy where polrelid = 'public.app_incidents'::regclass and polname = 'Allow service_role full access on app_incidents') then
    create policy "Allow service_role full access on app_incidents" on public.app_incidents
      for all to service_role using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policy where polrelid = 'public.firmware_updates'::regclass and polname = 'Allow public read access for firmware updates') then
    create policy "Allow public read access for firmware updates" on public.firmware_updates
      for select using (true);
  end if;
  if not exists (select 1 from pg_policy where polrelid = 'public.health_engine_config'::regclass and polname = 'health_engine_config_read') then
    create policy "health_engine_config_read" on public.health_engine_config for select using (true);
  end if;
  if not exists (select 1 from pg_policy where polrelid = 'public.health_engine_config'::regclass and polname = 'health_engine_config_write') then
    create policy "health_engine_config_write" on public.health_engine_config for all
      using (auth.role() = 'service_role') with check (auth.role() = 'service_role');
  end if;
end $$;

-- Caregiver / alerting policies.

do $$ begin
  if not exists (select 1 from pg_policy where polrelid = 'public.caregiver_link_requests'::regclass and polname = 'caregiver_link_requests_requester') then
    create policy "caregiver_link_requests_requester" on public.caregiver_link_requests
      for all using (auth.uid() = requester_id) with check (auth.uid() = requester_id);
  end if;
  if not exists (select 1 from pg_policy where polrelid = 'public.caregiver_link_requests'::regclass and polname = 'caregiver_link_requests_target_read') then
    create policy "caregiver_link_requests_target_read" on public.caregiver_link_requests
      for select using (auth.uid() = target_user_id);
  end if;
  if not exists (select 1 from pg_policy where polrelid = 'public.caregiver_link_requests'::regclass and polname = 'caregiver_link_requests_target_update') then
    create policy "caregiver_link_requests_target_update" on public.caregiver_link_requests
      for update using (auth.uid() = target_user_id) with check (auth.uid() = target_user_id);
  end if;
  if not exists (select 1 from pg_policy where polrelid = 'public.caregiver_links'::regclass and polname = 'caregiver_links_read') then
    create policy "caregiver_links_read" on public.caregiver_links
      for select using (auth.uid() in (wearer_user_id, caregiver_user_id));
  end if;
  if not exists (select 1 from pg_policy where polrelid = 'public.caregiver_links'::regclass and polname = 'caregiver_links_insert') then
    create policy "caregiver_links_insert" on public.caregiver_links
      for insert with check (auth.uid() = wearer_user_id);
  end if;
  if not exists (select 1 from pg_policy where polrelid = 'public.caregiver_links'::regclass and polname = 'caregiver_links_delete') then
    create policy "caregiver_links_delete" on public.caregiver_links
      for delete using (auth.uid() in (wearer_user_id, caregiver_user_id));
  end if;
  if not exists (select 1 from pg_policy where polrelid = 'public.emergency_alerts'::regclass and polname = 'emergency_alerts_owner') then
    create policy "emergency_alerts_owner" on public.emergency_alerts
      for all using (auth.uid() = wearer_user_id) with check (auth.uid() = wearer_user_id);
  end if;
  if not exists (select 1 from pg_policy where polrelid = 'public.emergency_alert_deliveries'::regclass and polname = 'emergency_alert_deliveries_owner_read') then
    create policy "emergency_alert_deliveries_owner_read" on public.emergency_alert_deliveries
      for select using (
        exists (
          select 1 from public.emergency_alerts a
          where a.id = alert_id and a.wearer_user_id = auth.uid()
        )
      );
  end if;
end $$;

-- ── Grants (RLS policies alone don't grant API access) ───────────────────

grant select, insert, update, delete on public.user_profiles to authenticated;
grant select, insert, update, delete on public.user_steps to authenticated;
grant select, insert, update, delete on public.user_hr to authenticated;
grant select, insert, update, delete on public.user_spo2 to authenticated;
grant select, insert, update, delete on public.user_hrv to authenticated;
grant select, insert, update, delete on public.user_bp to authenticated;
grant select, insert, update, delete on public.user_stress to authenticated;
grant select, insert, update, delete on public.user_temp to authenticated;
grant select, insert, update, delete on public.user_workouts to authenticated;
grant select, insert, update, delete on public.workouts to authenticated;
grant select, insert, update, delete on public.user_sleep to authenticated;
grant select, insert, update, delete on public.user_cycles to authenticated;
grant select, insert, update, delete on public.user_symptoms to authenticated;
grant select, insert, update, delete on public.user_emergency_contacts to authenticated;
grant select, insert, update, delete on public.user_hr_readings to authenticated;
grant select, insert, update, delete on public.user_spo2_readings to authenticated;
grant select, insert, update, delete on public.user_hrv_readings to authenticated;
grant select, insert, update, delete on public.user_steps_snapshots to authenticated;
grant insert on public.app_incidents to anon, authenticated;
grant select on public.firmware_updates to anon, authenticated;
grant select, insert, update, delete on public.user_push_tokens to authenticated;
grant select, insert, update, delete on public.caregiver_link_requests to authenticated;
grant select, insert, update, delete on public.caregiver_links to authenticated;
grant select, insert, update, delete on public.emergency_alerts to authenticated;
grant select on public.emergency_alert_deliveries to authenticated;
grant select, insert, update, delete on public.user_ecg to authenticated;
grant select, insert, update, delete on public.user_breath_sessions to authenticated;
grant select, insert, update, delete on public.user_blood_sugar to authenticated;
grant select, insert, update, delete on public.user_quran_bookmarks to authenticated;
grant select, insert, update, delete on public.user_friends to authenticated;
grant select, insert, update, delete on public.user_nutrition_logs to authenticated;
grant select, insert, update, delete on public.user_watchface to authenticated;
grant select, insert, update, delete on public.falls to authenticated;
grant select on public.derived_user_cycles to authenticated;
grant select, insert, update, delete on public.conversations to authenticated;
grant select, insert, update, delete on public.messages to authenticated;

-- ── Functions ────────────────────────────────────────────────────────────

create or replace function public.resolve_sundr_user(p_phone text)
returns table (user_id uuid, full_name text)
language sql
security definer
set search_path = public
as $$
  with needle as (
    select regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g') as n
  )
  select p.id, p.full_name
  from public.user_profiles p, needle
  where p.phone is not null
    and regexp_replace(p.phone, '[^0-9+]', '', 'g') <> ''
    and needle.n <> ''
    and (
      regexp_replace(p.phone, '[^0-9+]', '', 'g') = needle.n
      or (
        length(needle.n) >= 10
        and right(regexp_replace(p.phone, '[^0-9+]', '', 'g'), 10) = right(needle.n, 10)
      )
    )
  order by (regexp_replace(p.phone, '[^0-9+]', '', 'g') = needle.n) desc
  limit 1;
$$;

grant execute on function public.resolve_sundr_user(text) to authenticated;

-- Account deletion: guarded per-table so partial DBs never raise
-- "relation does not exist". user_profiles keys on id, everything else
-- on user_id. health_engine_config is a global singleton: never deleted.

create or replace function public.delete_user_account()
returns void
language plpgsql
security definer
as $$
declare
  current_user_id uuid;
  t text;
begin
  current_user_id := auth.uid();

  if current_user_id is null then
    raise exception 'Not authenticated';
  end if;

  -- messages has no user_id; remove them before the conversation rows.
  if to_regclass('public.messages') is not null
     and to_regclass('public.conversations') is not null then
    execute format(
      'delete from public.messages where conversation_id in (select id from public.conversations where user_id = %L)',
      current_user_id
    );
  end if;

  foreach t in array array[
    'user_profiles','user_bp','user_stress','user_temp',
    'user_workouts','user_sleep','user_cycles','user_symptoms',
    'user_emergency_contacts','user_steps','user_hr','user_spo2','user_hrv',
    'user_hr_readings','user_spo2_readings','user_hrv_readings',
    'user_steps_snapshots','workouts','user_push_tokens',
    'user_blood_sugar','user_breath_sessions','user_ecg',
    'user_quran_bookmarks','user_friends','user_nutrition_logs',
    'user_watchface','falls','conversations'
  ]
  loop
    if to_regclass(format('public.%I', t)) is not null then
      if t = 'user_profiles' then
        if exists (select 1 from information_schema.columns
                   where table_schema = 'public' and table_name = t
                     and column_name = 'id') then
          execute format('delete from public.user_profiles where id = %L', current_user_id);
        end if;
      else
        if exists (select 1 from information_schema.columns
                   where table_schema = 'public' and table_name = t
                     and column_name = 'user_id') then
          execute format('delete from public.%I where user_id = %L', t, current_user_id);
        end if;
      end if;
    end if;
  end loop;

  if to_regclass('public.emergency_alert_deliveries') is not null then
    execute format(
      'delete from public.emergency_alert_deliveries where alert_id in ' ||
      '(select id from public.emergency_alerts where wearer_user_id = %L)',
      current_user_id
    );
  end if;
  if to_regclass('public.emergency_alerts') is not null then
    execute format('delete from public.emergency_alerts where wearer_user_id = %L', current_user_id);
  end if;
  if to_regclass('public.caregiver_links') is not null then
    execute format(
      'delete from public.caregiver_links where wearer_user_id = %L or caregiver_user_id = %L',
      current_user_id, current_user_id
    );
  end if;
  if to_regclass('public.caregiver_link_requests') is not null then
    execute format(
      'delete from public.caregiver_link_requests where requester_id = %L or target_user_id = %L',
      current_user_id, current_user_id
    );
  end if;

  delete from auth.users where id = current_user_id;
end;
$$;

grant execute on function public.delete_user_account() to authenticated;
