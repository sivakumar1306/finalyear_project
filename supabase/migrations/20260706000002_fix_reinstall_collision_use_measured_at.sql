-- Fixes a real data-corruption bug: local_reading_id is Room's local auto-increment
-- primary key, which RESETS to 1 after every app reinstall/uninstall. Since the previous
-- uniqueness constraint was (user_id, local_reading_id), a freshly reinstalled app's new
-- rows (starting again at local_reading_id=1) could collide with and silently OVERWRITE
-- unrelated historical rows from a previous install that happened to reuse the same id —
-- confirmed happening during testing (three real readings overwrote unrelated older rows
-- that shared the same local_reading_id after a reinstall).
--
-- Fix: use the actual measurement timestamp as the idempotency key instead. measured_at/
-- captured_at are real wall-clock times set at the moment of measurement — they are never
-- reset by a reinstall, and two genuinely different readings for the same user essentially
-- never share the same millisecond timestamp given the app's sequential, cooldown-gated
-- measurement loop. local_reading_id columns are kept (useful for local traceability) but
-- no longer participate in the uniqueness constraint.

alter table public.user_hr_readings
  drop constraint if exists user_hr_readings_user_id_local_reading_id_key;
alter table public.user_hr_readings
  add constraint user_hr_readings_user_measured_key unique (user_id, measured_at);

alter table public.user_spo2_readings
  drop constraint if exists user_spo2_readings_user_id_local_reading_id_key;
alter table public.user_spo2_readings
  add constraint user_spo2_readings_user_measured_key unique (user_id, measured_at);

alter table public.user_hrv_readings
  drop constraint if exists user_hrv_readings_user_id_local_reading_id_key;
alter table public.user_hrv_readings
  add constraint user_hrv_readings_user_measured_key unique (user_id, measured_at);

alter table public.user_steps_snapshots
  drop constraint if exists user_steps_snapshots_user_id_local_reading_id_key;
alter table public.user_steps_snapshots
  add constraint user_steps_snapshots_user_captured_key unique (user_id, captured_at);

alter table public.user_bp
  drop constraint if exists user_bp_local_reading_key;
alter table public.user_bp
  add constraint user_bp_user_measured_key unique (user_id, measured_at);

alter table public.user_stress
  drop constraint if exists user_stress_local_reading_key;
alter table public.user_stress
  add constraint user_stress_user_measured_key unique (user_id, measured_at);

alter table public.user_temp
  drop constraint if exists user_temp_local_reading_key;
alter table public.user_temp
  add constraint user_temp_user_measured_key unique (user_id, measured_at);
