-- 20260914000000_add_default_emergency_contact.sql
-- Adds default_emergency_contact column to user_profiles table.

alter table public.user_profiles 
add column if not exists default_emergency_contact text default '101';
