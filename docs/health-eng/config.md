# Config — Single Dict, Supabase-Updatable

One JSONB column is the entire contract. All thresholds + literals/ranges live in it, so product can tune bands or copy without shipping a new build.

## Table

`supabase/migrations/20260905000000_health_engine_config.sql`:

```sql
create table if not exists public.health_engine_config (
  id int primary key,               -- always 1 (singleton row)
  config jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.health_engine_config enable row level security;

-- singleton seed — defaults match lib/services/health_engine/health_config.dart:kDefaultConfig
insert into public.health_engine_config (id, config) values (1, '{}'::jsonb)
on conflict (id) do nothing;

-- read for all authenticated users, write only service_role / admin (tune as needed)
-- app uses anon key → authenticated read is enough for thresholds
create policy "health_engine_config_read" on public.health_engine_config
  for select using (auth.role() = 'authenticated' or auth.role() = 'anon');
-- writes via dashboard/service_role; add restrictive policy if exposing admin UI
create policy "health_engine_config_write" on public.health_engine_config
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

create or replace function public.touch_health_engine_config()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

drop trigger if exists trg_touch_health_engine_config on public.health_engine_config;
create trigger trg_touch_health_engine_config
  before update on public.health_engine_config
  for each row execute function public.touch_health_engine_config();
```

Rationale: singleton row `id=1` keeps fetch trivial (`eq('id',1).maybeSingle()`), avoids key/value table joins, and lets Studio edit one JSONB cell.

## JSON shape

See `health_config.dart:kDefaultConfig` for the full default payload. Remote value deep-merges over it:

```json
{
  "version": 1,
  "thresholds": {
    "sleep":   {"excellent":80,"good":60,"fair":40},
    "hr":      {"belowNormal":60,"aboveNormal":100},
    "spo2":    {"normal":95,"borderline":90},
    "hrv":     {"veryLow":20,"low":40,"moderate":60,"good":80},
    "stress":  {"relaxed":40,"normal":60,"elevated":80},
    "bp":      {"normalSbp":120,"normalDbp":80,"elevatedSbp":130,"stage1Sbp":140,"stage1Dbp":90},
    "temp":    {"low":36.0,"normal":37.2,"elevated":38.0},
    "activity":{"stepsWeight":60,"caloriesWeight":25,"distanceWeight":15,"stepsDenom":10000,"caloriesDenom":1000,"distanceDenomM":5000}
  },
  "advice": {
    "sleep": {"title":"Sleep","heading":"About Sleep","intro":"...","didYouKnow":"...","tips":[{"icon":"bedtime_rounded","color":"sleepColor","title":"Aim for 7–9 hours","tip":"..."}]},
    "heartRate": {"title":"Heart Rate","heading":"About Heart Rate","intro":"...","didYouKnow":"...","tips":[...]},
    "spo2": {...}, "hrv": {...}, "stress": {...}, "temperature": {...}, "bloodPressure": {...}, "activity": {...}
  },
  "ranges": {
    "sleep": [{"label":"Poor","range":"0–39","color":"danger"}, {"label":"Fair","range":"40–59","color":"amber"}, {"label":"Good","range":"60–79","color":"sleepColor"}, {"label":"Excellent","range":"80–100","color":"success"}],
    "heartRate": [{"label":"Below normal","range":"<60 bpm","color":"hrvColor"}, ...],
    ...
  }
}
```

* `thresholds` — numbers only. Changing `sleep.excellent` from 80→85 makes Home + Detail flip together (fixes the original bug).
* `advice` + `ranges` — same row, so copy and thresholds stay versioned together. Icons/colors use string keys (`"sleepColor"`, `"bedtime_rounded"`) → engine maps to `AppTheme.*` / `Icons.*`.
* `activity` denoms (`stepsDenom` etc.) are fallbacks when `GoalPrefs` has no user value yet; at runtime `GoalPrefs` overrides them (see `activity.md`).

Partial updates allowed: send only `{"thresholds":{"sleep":{"excellent":85}}}` — deep-merge keeps everything else at default.

## Fetch path

`lib/services/health_engine/health_config.dart`:

```dart
class HealthConfig {
  static Map<String,dynamic> _current = kDefaultConfig;
  static Map<String,dynamic> get current => _current;

  // 1) Try Supabase: client.from('health_engine_config').select('config').eq('id',1).maybeSingle()
  // 2) Cache success to SharedPreferences 'health_engine_config_json' + 'health_engine_config_updated_at'
  // 3) On failure/offline: load SharedPreferences cache
  // 4) On cache miss: use kDefaultConfig
  // 5) Deep-merge remote over default: _current = merge(default, remote)
  static Future<void> load() async { ... }
  static Future<void> refresh() => load();
}
```

Called once in `lib/main.dart` (`await HealthConfig.load()`) before `runApp`, plus:

* `BleProvider` / `HomeScreen` pull-to-refresh → `await HealthConfig.refresh()`
* `didChangeAppLifecycleState.resumed` → opportunistic `refresh()` if `updated_at` stale >5 min (TTL in `HealthConfig.kCacheTtl`).

No polling. Supabase Realtime subscription is optional (not enabled in v1 — add `config` channel later if live tuning without resume is needed).

## Studio workflow

1. Supabase Studio → Table Editor → `health_engine_config` → row `id=1` → `config`.
2. Edit JSON (use Studio’s JSONB editor, validate).
3. Save → next app resume / pull-to-refresh picks it up. Bump `version` if you want clients to force-refresh even when merge logic would otherwise skip.

## Safety

* Validation: `HealthEngine` clamps nonsensical values (e.g. `excellent` outside 0–100 falls back to default). Logs via `IncidentService` if remote JSON parse fails.
* RLS: `anon`/`authenticated` can select; only `service_role` can update (dashboard uses service_role key). Don’t grant `authenticated` write or any user can retune medical bands.
* Bundled fallback ensures offline-first: airplane mode never shows `--` purely because config couldn’t load.

## Migration notes

`20260905000000_health_engine_config.sql` is idempotent (`if not exists`) and safe to run on live DB with manual tables. Existing `delete_user_account()` does **not** need to touch this table (global, not per-user).

