-- Assist chat history. The MedXAI API writes these with the service role.
-- The Flutter client reads them only through that API.
-- Safe to re-run.

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

alter table public.messages add column if not exists card jsonb;

alter table public.conversations enable row level security;
alter table public.messages enable row level security;

do $$ begin
  if not exists (
    select 1 from pg_policy
    where polrelid = 'public.conversations'::regclass and polname = 'conversations_owner'
  ) then
    create policy conversations_owner on public.conversations
      for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
  end if;
  if not exists (
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

grant select, insert, update, delete on public.conversations to authenticated;
grant select, insert, update, delete on public.messages to authenticated;

-- Same delete_user_account as init, plus chat transcripts.
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
