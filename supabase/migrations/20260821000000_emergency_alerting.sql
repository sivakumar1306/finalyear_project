-- 20260821000000_emergency_alerting.sql
-- Emergency alerting subsystem (client-approved plan, docs/sms/emergency-alerting-system.md):
--
--   * user_profiles.phone          — phone→Sundr-account resolution (the Dart app already
--                                    writes `phone` via upsertProfile; the column never
--                                    existed in any migration, so those writes failed).
--   * user_push_tokens             — FCM tokens per Sundr user (in-app companion alerts).
--   * caregiver_link_requests      — the "friend request" flow: wearer asks a Sundr user
--                                    to become their emergency contact; two-sided consent.
--   * caregiver_links              — accepted links. ONLY these receive FCM push alerts.
--   * emergency_alerts             — one row per alert raised (ledger / cooldown anchor).
--   * emergency_alert_deliveries   — per-recipient, per-channel attempt ledger
--                                    (device_sms / cloud_sms / fcm_push → status), giving
--                                    real delivery proof instead of fire-and-forget.
--
-- Phone normalization convention (must match Dart/Kotlin/Edge-Function side):
--   normalized = regexp_replace(phone, '[^0-9+]', '', 'g')   -- keep digits + leading '+'
--
-- Idempotent: guarded ALTERs + IF NOT EXISTS + policy guards, safe to re-run.

-- ── user_profiles.phone ──────────────────────────────────────────────────────

alter table public.user_profiles add column if not exists phone text;

create index if not exists user_profiles_phone_norm_idx
  on public.user_profiles (regexp_replace(coalesce(phone, ''), '[^0-9+]', '', 'g'));

-- ── FCM push tokens ──────────────────────────────────────────────────────────

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

-- ── Caregiver link requests (request → accept/decline) ───────────────────────

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

-- ── Accepted caregiver links ─────────────────────────────────────────────────

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

-- ── Alert ledger + per-recipient delivery attempts ───────────────────────────

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

-- ── Row Level Security ───────────────────────────────────────────────────────

alter table public.user_push_tokens enable row level security;
alter table public.caregiver_link_requests enable row level security;
alter table public.caregiver_links enable row level security;
alter table public.emergency_alerts enable row level security;
alter table public.emergency_alert_deliveries enable row level security;

do $$
begin
  -- Push tokens: owner-only.
  if not exists (select 1 from pg_policy where polrelid = 'public.user_push_tokens'::regclass and polname = 'user_push_tokens_owner') then
    create policy "user_push_tokens_owner" on public.user_push_tokens
      for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
  end if;

  -- Link requests: requester full control of own rows; target can read + respond.
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
      for update using (auth.uid() = target_user_id)
      with check (auth.uid() = target_user_id);
  end if;

  -- Links: both parties can read; either party can remove their link.
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

  -- Alerts: wearer-only.
  if not exists (select 1 from pg_policy where polrelid = 'public.emergency_alerts'::regclass and polname = 'emergency_alerts_owner') then
    create policy "emergency_alerts_owner" on public.emergency_alerts
      for all using (auth.uid() = wearer_user_id) with check (auth.uid() = wearer_user_id);
  end if;

  -- Deliveries: written by edge functions (service role bypasses RLS); the wearer
  -- can read the delivery trail of their own alerts.
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

-- ── resolve_sundr_user(p_phone) — privacy-safe phone → account lookup ────────
-- Returns at most one match: exact normalized-phone match first, then a
-- last-10-digits match (covers +91 / 0-prefix country-code differences).
-- SECURITY DEFINER so the caller never needs read access to other profiles.

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

-- ── Account deletion: wipe the new tables too ────────────────────────────────
-- Mirrors 20260807000000_fix_delete_user_account.sql (defensive, table-existence
-- checked) and adds the alerting tables. emergency_alert_deliveries cascades from
-- emergency_alerts; caregiver_* use non-user_id key columns so they are handled
-- explicitly rather than via the generic user_id loop.

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

  -- Chat children first (legacy tables — only touched when they actually exist
  -- and carry the columns the query relies on).
  if to_regclass('public.messages') is not null
     and to_regclass('public.conversations') is not null
     and exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'messages'
                   and column_name = 'conversation_id')
     and exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'conversations'
                   and column_name = 'user_id') then
    execute format(
      'delete from public.messages where conversation_id in ' ||
      '(select id from public.conversations where user_id = %L)',
      current_user_id
    );
  end if;

  -- All user-scoped tables keyed on user_id (or id, for user_profiles).
  foreach t in array array[
    'conversations','vital_readings','sedentary_alerts','workout_analytics',
    'sleep_sessions','ring_sync_cache','activity_goals','sedentary_logs',
    'workout_sessions','medical_events','medications','lab_reports',
    'user_blood_panels','user_profiles','user_bp','user_stress','user_temp',
    'user_workouts','user_sleep','user_cycles','user_symptoms',
    'user_emergency_contacts','user_steps','user_hr','user_spo2','user_hrv',
    'user_hr_readings','user_spo2_readings','user_hrv_readings',
    'user_steps_snapshots','workouts','user_push_tokens'
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

  -- Alerting tables with non-user_id key columns.
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

  -- Finally, destroy the auth account (cascades to any remaining FK'd rows).
  delete from auth.users where id = current_user_id;
end;
$$;
