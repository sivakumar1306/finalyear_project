-- Phase 3/4: Social, Quran, Nutrition, Watchface, GPS

create table if not exists public.user_quran_bookmarks (
  user_id uuid not null references auth.users(id) on delete cascade,
  chapter_index int not null,
  is_collection boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (user_id, chapter_index)
);
alter table public.user_quran_bookmarks enable row level security;
do $$ begin if not exists (select 1 from pg_policies where tablename='user_quran_bookmarks') then create policy "owner can manage quran" on public.user_quran_bookmarks for all using (auth.uid()=user_id) with check (auth.uid()=user_id); end if; end $$;

create table if not exists public.user_friends (
  user_id uuid not null references auth.users(id) on delete cascade,
  friend_user_id text not null,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  primary key (user_id, friend_user_id)
);
alter table public.user_friends enable row level security;
do $$ begin if not exists (select 1 from pg_policies where tablename='user_friends') then create policy "owner can manage friends" on public.user_friends for all using (auth.uid()=user_id) with check (auth.uid()=user_id); end if; end $$;

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
alter table public.user_nutrition_logs enable row level security;
do $$ begin if not exists (select 1 from pg_policies where tablename='user_nutrition_logs') then create policy "owner can manage nutrition" on public.user_nutrition_logs for all using (auth.uid()=user_id) with check (auth.uid()=user_id); end if; end $$;

create table if not exists public.user_watchface (
  user_id uuid not null references auth.users(id) on delete cascade,
  installed_name text not null,
  installed_at timestamptz not null default now(),
  primary key (user_id)
);
alter table public.user_watchface enable row level security;
do $$ begin if not exists (select 1 from pg_policies where tablename='user_watchface') then create policy "owner can manage watchface" on public.user_watchface for all using (auth.uid()=user_id) with check (auth.uid()=user_id); end if; end $$;

-- Extend delete_user_account for new tables
create or replace function public.delete_user_account() returns void language plpgsql security definer as $$
declare r record;
begin
  for r in select tablename from pg_tables where schemaname='public' and tablename in ('user_quran_bookmarks','user_friends','user_nutrition_logs','user_watchface','user_blood_sugar','user_breath_sessions','user_ecg','user_hr','user_spo2','user_hrv','user_steps','user_bp','user_stress','user_temp','user_sleep','user_cycles','user_symptoms','user_profiles','user_emergency_contacts','user_push_tokens')
  loop execute format('delete from public.%I where user_id = $1', r.tablename) using auth.uid(); end loop;
  delete from auth.users where id = auth.uid();
end; $$;
