# BP Staging — Alias Plan

> After all logic transferred, keep `lib/utils/bp_staging.dart` as alias to `HealthEngine` (per requirement).

## Current Duplicate

* `bp_staging.dart:40` `classifyBp(sbp,dbp) <120/80 normal <130/80 elevated <140/90 stage1 else stage2` hard-coded.
* `health_engine.dart:176` `assessBloodPressure` same thresholds via `HealthConfig.intThreshold('bp',...)` remote-tunable.

## Alias Implementation

```dart
// lib/utils/bp_staging.dart — after HealthEngine is single truth
import '../services/health_engine/health_engine.dart';

BpStage classifyBp(int sbp, int dbp) {
  final a = HealthEngine.instance.assessBloodPressure(sbp, dbp);
  return switch(a.label) {
    'Normal' => BpStage.normal,
    'Elevated' => BpStage.elevated,
    'Stage 1' => BpStage.stage1,
    'Stage 2' => BpStage.stage2,
    _ => BpStage.noData,
  };
}
Color bpStatusColor(...) => HealthEngine.instance.assessBloodPressure(sbp,dbp).color;
```

`BpStage` enum + `label/compactLabel` stays (pure model). Hard-coded `120/80/130/140/90` removed.

## Deletion of Wrappers

After alias, delete free funcs `blood_pressure_screen.dart:43 _bpStatus`, `home_compact_cards.dart:254 _bpCompactStatus`, `hrv_screen:122 _hrvLabel`, `stress_screen:48 _stressLabel`, `temperature_screen:123 _tempLabel`, `home_screen:174 _spo2Status/_hrStatus/_hrvStatus/_sleepStatus`, `home_card_shared:70 stressStatus/tempStatus/activityScoreLabel` — call sites use `HealthEngine.instance.assess*(v).label` directly.

## Verification

`test/bp_staging_test.dart` already covers `110/70 normal`, `125/75 elevated`, `135/85 stage1`, `145/95 stage2`, `120/80 stage1`, `140/89 stage2`. After alias, same tests pass but now driven by config.
