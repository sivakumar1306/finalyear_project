-- 20260905000000_health_engine_config.sql
-- Single source of truth for HealthEngine thresholds + advice literals.
-- One JSONB row (id=1) deep-merged over the bundled default in
-- lib/services/health_engine/health_config.dart:kDefaultConfig.
-- This lets product tune bands/copy via Supabase without app update.
-- Idempotent and additive — safe on live DB.

create table if not exists public.health_engine_config (
  id int primary key,
  config jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.health_engine_config enable row level security;

-- Seed singleton row with empty object so merge keeps defaults until first write.
insert into public.health_engine_config (id, config)
values (1, '{}'::jsonb)
on conflict (id) do nothing;

do $$
begin
  if not exists (
    select 1 from pg_policy
    where polrelid = 'public.health_engine_config'::regclass
      and polname = 'health_engine_config_read'
  ) then
    create policy "health_engine_config_read"
      on public.health_engine_config for select
      using (true);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policy
    where polrelid = 'public.health_engine_config'::regclass
      and polname = 'health_engine_config_write'
  ) then
    create policy "health_engine_config_write"
      on public.health_engine_config for all
      using (auth.role() = 'service_role')
      with check (auth.role() = 'service_role');
  end if;
end $$;

-- Keep updated_at fresh on any config edit (Studio or service_role).
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
