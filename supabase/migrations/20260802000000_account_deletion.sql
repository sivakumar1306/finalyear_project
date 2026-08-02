-- 20260802000000_account_deletion.sql
-- Function to permanently delete a user's account and all associated data.
-- This function runs with SECURITY DEFINER to bypass row-level security
-- and delete from auth.users, but it ONLY acts on auth.uid() to ensure
-- a user can only delete their own account.

CREATE OR REPLACE FUNCTION public.delete_user_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  current_user_id uuid;
BEGIN
  -- Get the current authenticated user's ID
  current_user_id := auth.uid();
  
  -- If no user is logged in, raise an exception
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Delete child tables first
  DELETE FROM public.messages WHERE conversation_id IN (SELECT id FROM public.conversations WHERE user_id = current_user_id);
  
  -- Delete all other tables referencing auth.users
  DELETE FROM public.conversations WHERE user_id = current_user_id;
  DELETE FROM public.vital_readings WHERE user_id = current_user_id;
  DELETE FROM public.sedentary_alerts WHERE user_id = current_user_id;
  DELETE FROM public.workout_analytics WHERE user_id = current_user_id;
  DELETE FROM public.sleep_sessions WHERE user_id = current_user_id;
  DELETE FROM public.ring_sync_cache WHERE user_id = current_user_id;
  DELETE FROM public.activity_goals WHERE user_id = current_user_id;
  DELETE FROM public.sedentary_logs WHERE user_id = current_user_id;
  DELETE FROM public.workout_sessions WHERE user_id = current_user_id;
  DELETE FROM public.medical_events WHERE user_id = current_user_id;
  DELETE FROM public.medications WHERE user_id = current_user_id;
  DELETE FROM public.lab_reports WHERE user_id = current_user_id;
  DELETE FROM public.user_blood_panels WHERE user_id = current_user_id;

  -- Delete existing handled tables
  DELETE FROM public.user_profiles WHERE id = current_user_id;
  DELETE FROM public.user_bp WHERE user_id = current_user_id;
  DELETE FROM public.user_stress WHERE user_id = current_user_id;
  DELETE FROM public.user_temp WHERE user_id = current_user_id;
  DELETE FROM public.user_workouts WHERE user_id = current_user_id;
  DELETE FROM public.user_sleep WHERE user_id = current_user_id;
  DELETE FROM public.user_cycles WHERE user_id = current_user_id;
  DELETE FROM public.user_symptoms WHERE user_id = current_user_id;
  DELETE FROM public.user_emergency_contacts WHERE user_id = current_user_id;
  DELETE FROM public.user_steps WHERE user_id = current_user_id;
  DELETE FROM public.user_hr WHERE user_id = current_user_id;
  DELETE FROM public.user_spo2 WHERE user_id = current_user_id;
  DELETE FROM public.user_hrv WHERE user_id = current_user_id;
  DELETE FROM public.user_hr_readings WHERE user_id = current_user_id;
  DELETE FROM public.user_spo2_readings WHERE user_id = current_user_id;
  DELETE FROM public.user_hrv_readings WHERE user_id = current_user_id;
  DELETE FROM public.user_steps_snapshots WHERE user_id = current_user_id;

  -- Finally, delete the user from auth.users.
  -- This will destroy the user's login credentials and session.
  DELETE FROM auth.users WHERE id = current_user_id;
END;
$$;
