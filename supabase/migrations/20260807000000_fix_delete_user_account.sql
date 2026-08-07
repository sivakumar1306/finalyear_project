-- 20260807000000_fix_delete_user_account.sql
-- Two fixes, both required for a migration-only (fresh) database:
--
-- 1. `delete_user_account()` previously hard-coded DELETEs against legacy tables
--    (messages, conversations, vital_readings, sedentary_*, workout_analytics,
--    sleep_sessions, ring_sync_cache, activity_goals, medical_events,
--    medications, lab_reports, user_blood_panels) that NO migration creates.
--    On a fresh `supabase db push` the first DELETE raised
--    `relation "public.messages" does not exist` and account deletion was
--    broken end-to-end. The function now deletes only from tables that exist
--    (and only when they carry the expected key column), so it works on both
--    the live DB (legacy tables present) and fresh DBs (legacy tables absent).
--
-- 2. `user_bp` / `user_stress` are created by `20260806000000_missing_tables.sql`
--    WITHOUT the (user_id, measured_at) unique constraint that the native
--    `SupabaseSyncManager` pushes target via `on_conflict=user_id,measured_at`
--    (PostgREST requires a full, non-partial unique constraint matching the ON
--    CONFLICT specification; a missing one is a hard 42P10/400 error per push).
--    On the live DB the constraint was added by 20260706000002 when the tables
--    existed manually; on a fresh DB it never was. Add it here, guarded.

-- ── Fix 2: idempotent (user_id, measured_at) unique constraints ───────────────

do $$
begin
  if to_regclass('public.user_bp') is not null then
    begin
      alter table public.user_bp
        add constraint user_bp_user_measured_key unique (user_id, measured_at);
    exception when duplicate_table then
      null; -- constraint already present (e.g. live DB via 20260706000002)
    end;
  end if;
end $$;

do $$
begin
  if to_regclass('public.user_stress') is not null then
    begin
      alter table public.user_stress
        add constraint user_stress_user_measured_key unique (user_id, measured_at);
    exception when duplicate_table then
      null;
    end;
  end if;
end $$;

-- user_temp carries `unique (user_id, measured_at)` inline in missing_tables;
-- re-assert it here for pre-existing live tables that may lack it.
do $$
begin
  if to_regclass('public.user_temp') is not null then
    begin
      alter table public.user_temp
        add constraint user_temp_user_measured_key unique (user_id, measured_at);
    exception when duplicate_table then
      null;
    end;
  end if;
end $$;

-- ── Fix 1: defensive account deletion ─────────────────────────────────────────

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

  -- All user-scoped tables. `user_profiles` keys on `id`; every other table
  -- keys on `user_id`. Tables that don't exist (or lack the key column) are
  -- skipped, so a migration-only database never raises "relation does not exist".
  foreach t in array array[
    'conversations','vital_readings','sedentary_alerts','workout_analytics',
    'sleep_sessions','ring_sync_cache','activity_goals','sedentary_logs',
    'workout_sessions','medical_events','medications','lab_reports',
    'user_blood_panels','user_profiles','user_bp','user_stress','user_temp',
    'user_workouts','user_sleep','user_cycles','user_symptoms',
    'user_emergency_contacts','user_steps','user_hr','user_spo2','user_hrv',
    'user_hr_readings','user_spo2_readings','user_hrv_readings',
    'user_steps_snapshots','workouts'
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

  -- Finally, destroy the auth account (cascades to any remaining FK'd rows).
  delete from auth.users where id = current_user_id;
end;
$$;
