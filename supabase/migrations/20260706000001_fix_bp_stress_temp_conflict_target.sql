-- Fixes: SupabaseSyncManager's push to user_bp/user_stress/user_temp fails with
-- "HTTP 400 42P10: there is no unique or exclusion constraint matching the ON CONFLICT
-- specification". PostgREST's on_conflict= parameter can only target a full (non-partial)
-- unique constraint — the partial unique index added in the previous migration
-- (`where local_reading_id is not null`) doesn't qualify.
--
-- A plain, non-partial UNIQUE constraint on (user_id, local_reading_id) is safe here:
-- Postgres treats every NULL as distinct from every other NULL for uniqueness purposes,
-- so the many pre-existing manual-flow rows (local_reading_id IS NULL) are unaffected —
-- only rows where local_reading_id is actually set (the native push) get deduplicated.

drop index if exists public.user_bp_local_reading_idx;
alter table public.user_bp
  add constraint user_bp_local_reading_key unique (user_id, local_reading_id);

drop index if exists public.user_stress_local_reading_idx;
alter table public.user_stress
  add constraint user_stress_local_reading_key unique (user_id, local_reading_id);

drop index if exists public.user_temp_local_reading_idx;
alter table public.user_temp
  add constraint user_temp_local_reading_key unique (user_id, local_reading_id);
