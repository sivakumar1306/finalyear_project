-- Phase 2: Detailed Health (ECG, Breath, Blood Sugar) — QRing parity
-- Mirrors QRing tables: qc_ecg_entity, breath_training_record, app_continuous_sugar

-- ECG waveform (per-sample)
create table if not exists public.user_ecg (
  user_id uuid not null references auth.users(id) on delete cascade,
  measured_at timestamptz not null,
  avg_heart int not null default 0,
  data_list jsonb not null default '[]'::jsonb,
  type int not null default 0,
  created_at timestamptz not null default now(),
  primary key (user_id, measured_at)
);
alter table public.user_ecg enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='user_ecg') then
    create policy "owner can manage user_ecg" on public.user_ecg for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
  end if;
end $$;

-- Breath sessions
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
alter table public.user_breath_sessions enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='user_breath_sessions') then
    create policy "owner can manage user_breath_sessions" on public.user_breath_sessions for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
  end if;
end $$;

-- Blood Sugar continuous (mirrors app_continuous_sugar 1/h)
create table if not exists public.user_blood_sugar (
  user_id uuid not null references auth.users(id) on delete cascade,
  measured_at timestamptz not null,
  min_sugar int not null,
  max_sugar int not null,
  hour int not null,
  created_at timestamptz not null default now(),
  primary key (user_id, measured_at)
);
alter table public.user_blood_sugar enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='user_blood_sugar') then
    create policy "owner can manage user_blood_sugar" on public.user_blood_sugar for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
  end if;
end $$;

-- Extend delete_user_account to new tables (idempotent)
create or replace function public.delete_user_account() returns void
language plpgsql security definer
as $$
declare r record;
begin
  for r in select tablename from pg_tables where schemaname='public' and tablename in
    ('user_blood_sugar','user_breath_sessions','user_ecg','user_hr','user_spo2','user_hrv','user_steps','user_bp','user_stress','user_temp','user_sleep','user_cycles','user_symptoms','user_profiles','user_emergency_contacts','user_push_tokens')
  loop
    execute format('delete from public.%I where user_id = $1', r.tablename) using auth.uid();
  end loop;
  delete from auth.users where id = auth.uid();
end; $$;
