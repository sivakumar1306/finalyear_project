import '../../services/fall_prediction/layer1_physiology.dart' show BpSource;

class ActivityRecovery {
  final double value; // Metric representing fitness/recovery benefit
  const ActivityRecovery(this.value);
}

class ActivityExposure {
  final double value; // Ambulation-hours representing fall opportunity
  const ActivityExposure(this.value);
}

class Layer1Baselines {
  final double rolling14DayMedianHR;
  final double rolling28DayMeanHRV;
  final double rolling28DayStdDevHRV;
  final double baselineAdjustedTemp;
  final double? baselineSys;
  final double? baselineDia;
  
  const Layer1Baselines({
    required this.rolling14DayMedianHR,
    required this.rolling28DayMeanHRV,
    required this.rolling28DayStdDevHRV,
    required this.baselineAdjustedTemp,
    this.baselineSys,
    this.baselineDia,
  });
}

// Layer 1 Inputs: Physiological raw inputs
class Layer1PhysiologyData {
  final double? hr;    // Heart Rate
  final double? hrv;   // Heart Rate Variability
  final double? bp;    // Blood Pressure
  final double? spo2;  // Blood Oxygen
  final double? temp;  // Skin Temperature
  final List<double>? hrBuffer; // Buffer of recent HR readings
  final BpSource? bpSource; // Source of BP measurement
  final double? sys;  // Systolic BP
  final double? dia;  // Diastolic BP
  final Layer1Baselines? baselines; // Historical baselines

  Layer1PhysiologyData({
    required this.hr,
    required this.hrv,
    required this.bp,
    required this.spo2,
    required this.temp,
    this.hrBuffer,
    this.bpSource,
    this.sys,
    this.dia,
    this.baselines,
  });
}

class Layer2Baselines {
  final double baselineSlp;
  final double baselineSlq;
  final double baselineAct;
  final double baselineWkl;
  final double baselineStr;

  const Layer2Baselines({
    required this.baselineSlp,
    required this.baselineSlq,
    required this.baselineAct,
    required this.baselineWkl,
    required this.baselineStr,
  });
}

// Layer 2 Inputs: Recovery raw inputs
class Layer2RecoveryData {
  final double? slp; // Sleep duration
  final double? slq; // Sleep quality
  final ActivityRecovery? act; // Activity
  final double? wkl; // Workout load
  final double? str; // Stress
  final Layer2Baselines? baselines; // Historical baselines

  Layer2RecoveryData({
    required this.slp,
    required this.slq,
    required this.act,
    required this.wkl,
    required this.str,
    this.baselines,
  });
}

class Layer3Baselines {
  final double baselineAcc;
  final double baselineGyr;
  final double baselineGait;
  final double baselinePsw;
  final double baselineOrtho;
  final double baselinePlnt;

  const Layer3Baselines({
    required this.baselineAcc,
    required this.baselineGyr,
    required this.baselineGait,
    required this.baselinePsw,
    required this.baselineOrtho,
    required this.baselinePlnt,
  });
}

// Layer 3 Inputs: Motion Stability raw inputs
class Layer3MotionData {
  final double? acc;   // Accelerometer-derived resultant acceleration magnitude
  final double? gyr;   // Gyroscope-derived angular velocity
  final double? gait;  // Gait consistency / variability
  final double? psw;   // Postural sway (from patent 003, claims 21–23)
  final double? ortho; // Orthostatic HR/BP trajectory after posture change
  final double? plnt;  // Plantar pressure array signal
  final double? fh;    // Fall history (single home: Layer 3 only)
  final ActivityExposure? actExp; // Activity exposure (ambulation hours)
  final Layer3Baselines? baselines; // Historical baselines

  Layer3MotionData({
    required this.acc,
    required this.gyr,
    required this.gait,
    required this.psw,
    required this.ortho,
    required this.plnt,
    required this.fh,
    required this.actExp,
    this.baselines,
  });
}

// Layer 4 Inputs: Women's Health
enum CycleState {
  active,
  postMenopause,
  preMenarche,
  hormonalContraception,
  optedOut,
}

class Layer4WomensHealthData {
  final bool isApplicable;
  final bool hasConsentedToWomensHealth;
  final CycleState cycleState;
  final int daysSinceLastPeriod;
  final int cycleLength;
  final bool isPMS;

  Layer4WomensHealthData({
    required this.isApplicable,
    required this.hasConsentedToWomensHealth,
    required this.cycleState,
    required this.daysSinceLastPeriod,
    required this.cycleLength,
    required this.isPMS,
  });
}
