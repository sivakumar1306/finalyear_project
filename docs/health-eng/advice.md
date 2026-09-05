# Advice & Comments — Engine-Owned Literals

Every human-facing string about a vital (heading, intro, `VitalRange` band labels, `VitalTip` cards, `didYouKnow`) used to be hard-coded inside each detail screen’s `_openMenu → VitalNoteScreen(...)`. They are now owned by the Health Engine and served via the same single dict as thresholds.

## Source

* **Bundled fallback:** `lib/services/health_engine/health_config.dart:kDefaultConfig['advice']` + `['ranges']`. Copy was moved verbatim from detail screens so no visual change.
* **Remote override:** same row `health_engine_config.config.advice` / `.ranges`. See `config.md` — Supabase JSONB overwrites the fallback via deep-merge.

## Detail → Engine mapping

| Metric | Detail screen that owned the copy | Engine accessor | Note fields |
|---|---|---|---|
| Sleep | `lib/screens/health/sleep_screen.dart:842` | `noteFor(HealthMetric.sleep)` | `title: Sleep`, `heading: About Sleep`, intro blends deep/REM, ranges Poor 0–39 … Excellent 80–100, tips “Aim 7–9h” / “Consistency”, didYouKnow deep vs REM |
| Heart Rate | `heart_rate_screen.dart:618` | `noteFor(HealthMetric.heartRate)` | Below/Normal/Above, tips Lower can be fine / Watch trend, didYouKnow caffeine |
| SpO₂ | `blood_oxygen_screen.dart:638` | `noteFor(HealthMetric.spo2)` | Normal/Borderline/Low, tips sleep dips / altitude, didYouKnow cold fingers |
| HRV | `hrv_screen.dart:662` | `noteFor(HealthMetric.hrv)` | Very Low … Excellent, tips personal / alcohol, didYouKnow rising trend |
| Stress | `stress_screen.dart:580` | `noteFor(HealthMetric.stress)` | Relaxed/Normal/Elevated/High, tips breathing / sleep debt, didYouKnow brief spike |
| Temperature | `temperature_screen.dart:658` | `noteFor(HealthMetric.temperature)` | Low/Normal/Elevated/Fever (Celsius), tips baseline / daily rhythm, didYouKnow skin vs core |
| Blood Pressure | `blood_pressure_screen.dart:655` | `noteFor(HealthMetric.bloodPressure)` | Normal/Elevated/Stage1/Stage2 with <120/80 etc, tips sodium / measure same way |
| Activity | `activity_description_screen.dart:51` | `noteFor(HealthMetric.activity)` | Weights Steps 60 / Calories 25 / Distance 15, range bar & legend, tips per metric |

Activity’s screen already existed; its weights/tips are now also served via `noteFor(HealthMetric.activity)` + `activity.md`.

## How a screen consumes it

Before (each screen duplicated):

```dart
Navigator.push(context, MaterialPageRoute(builder: (_) => const VitalNoteScreen(
  title: 'Sleep', heading: 'About Sleep', intro: 'Your ring tracks ...',
  ranges: [VitalRange(label:'Poor',range:'0–39',color:AppTheme.danger), ...],
  tips: [VitalTip(icon: Icons.bedtime_rounded, ...), ...],
  didYouKnow: 'Deep sleep handles ...',
)));
```

After:

```dart
final note = HealthEngine.instance.noteFor(HealthMetric.sleep);
Navigator.push(context, MaterialPageRoute(builder: (_) => VitalNoteScreen.fromData(note)));
// or VitalNoteScreen.fromMetric(HealthMetric.sleep)
```

`VitalNoteScreen.fromData` takes `VitalNoteData` (engine type) and maps `colorKey → AppTheme`. No screen owns copy.

## Config shape (advice + ranges)

```json
{
  "advice": {
    "sleep": {
      "title": "Sleep",
      "heading": "About Sleep",
      "intro": "Your ring tracks time asleep and cycles through light, deep, and REM stages — the sleep score blends duration and how unbroken that time was.",
      "didYouKnow": "Deep sleep handles physical recovery, REM handles memory and mood — you need a healthy mix of both.",
      "tips": [
        {"icon":"bedtime_rounded","color":"sleepColor","title":"Aim for 7–9 hours","tip":"Most adults need 7–9 hours ..."},
        {"icon":"schedule_rounded","color":"gold","title":"Consistency matters","tip":"Going to bed ..."}
      ]
    }
  },
  "ranges": {
    "sleep": [
      {"label":"Poor","range":"0–39","color":"danger"},
      {"label":"Fair","range":"40–59","color":"amber"},
      {"label":"Good","range":"60–79","color":"sleepColor"},
      {"label":"Excellent","range":"80–100","color":"success"}
    ]
  }
}
```

Icon strings are limited to the existing `Icons.*_rounded` set already used in each Note — engine maps `icon` string → `IconData` via `HealthEngine.tipIcon(String)`. Adding a new tip requires both config JSON and (if new icon) a one-line map addition.

## Updating copy without app update

1. In Supabase Studio → `health_engine_config` → edit `config` → `advice.sleep.tips[0].tip`.
2. Next `HealthConfig.refresh()` (Home pull-to-refresh, app resume, or `await HealthEngine.instance.refreshConfig()`) pulls it.
3. Offline: cached `SharedPreferences` value (`health_engine_config_json`) is used, so last-fetched copy survives.

## Home / detail “comments” (inline labels)

Small inline advice (“Below normal”, “Sedentary”, “Relaxed” badges) also come from the engine:

```dart
final a = HealthEngine.instance.assessHrv(value); // Assessment.label/color
Badge(color: a.color, label: a.label)
```

And trend comments (`InsightsService` headline “Your sleep is improving, but blood pressure is high”) now build from the same `assessmentFor` helpers, so headline wording can’t disagree with card label.

## Fall prediction

Not in this engine — `lib/services/fall_prediction/` remains separate. It may *read* engine assessments as inputs but never writes advice copy.

