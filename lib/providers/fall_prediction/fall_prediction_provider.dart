import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:math';

import '../../models/fall_prediction/physiological_data.dart';
import '../../models/fall_prediction/behavioral_data.dart';
import '../../models/fall_prediction/motion_data.dart';
import '../../models/fall_prediction/womens_health_data.dart';
import '../../models/fall_prediction/context_factors.dart';
import '../../models/fall_prediction/prediction_result.dart';
import '../../services/fall_prediction/fall_prediction_engine.dart';
import '../../services/health_connect_service.dart';

class FallPredictionProvider extends ChangeNotifier {
  final FallPredictionEngine _engine = FallPredictionEngine();
  
  PredictionResult? _currentResult;
  PredictionResult? get currentResult => _currentResult;

  StreamSubscription<UserAccelerometerEvent>? _accelSubscription;
  Timer? _healthSyncTimer;
  
  double _lastMagnitude = 0.0;
  
  // Baseline states (100 = perfect score, 0 = critical)
  PhysiologicalData _pData = PhysiologicalData(
    heartRate: 100, hrv: 100, bloodPressure: 100, spo2: 100, skinTemperature: 100,
  );
  
  BehavioralData _rData = BehavioralData(
    sleepDuration: 100, sleepQuality: 100, dailyActivity: 100, workoutLoad: 100, stress: 0,
  );
  
  final WomensHealthData _wData = WomensHealthData(
    isApplicable: false, daysSinceLastPeriod: 0, cycleLength: 28, isPMS: false,
  );
  
  final ContextFactors _context = ContextFactors();

  FallPredictionProvider() {
    _startSensorListeners();
    _fetchHealthData();
    // Poll health data every 5 minutes
    _healthSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) => _fetchHealthData());
  }
  
  Future<void> _fetchHealthData() async {
    final healthService = HealthConnectService.instance;
    final isAvailable = await healthService.isAvailable();
    if (!isAvailable) {
      _recalculate();
      return;
    }

    final types = await healthService.loadEnabledTypes();
    final today = await healthService.fetchToday(types);
    
    // Normalization logic: Mapping raw biological data to a 0-100 stability score.
    // 100 is optimal, 0 is severely degraded.
    
    // --- Physiological ---
    double hrScore = 100.0;
    if (today.avgHeartRate != null) {
      // Optimal resting HR ~ 60-70. Penalty for being too high or too low.
      hrScore = (100.0 - ((today.avgHeartRate! - 70).abs() * 1.5)).clamp(0.0, 100.0);
    }
    
    double hrvScore = 100.0;
    if (today.avgHrv != null) {
      // Higher HRV is generally better. 60+ is excellent.
      hrvScore = (today.avgHrv! / 60.0 * 100.0).clamp(0.0, 100.0);
    }
    
    double bpScore = 100.0;
    if (today.bpSystolic != null && today.bpDiastolic != null) {
      // Optimal BP is ~ 120/80
      double sysDiff = (today.bpSystolic! - 120).abs().toDouble();
      double diaDiff = (today.bpDiastolic! - 80).abs().toDouble();
      bpScore = (100.0 - (sysDiff + diaDiff) * 1.5).clamp(0.0, 100.0);
    }
    
    double spo2Score = 100.0;
    if (today.avgSpo2 != null) {
      // SpO2 should be 95%+. Drops below 95% aggressively reduce score.
      spo2Score = today.avgSpo2! >= 95 ? 100.0 : ((today.avgSpo2! - 80) / 15 * 100).clamp(0.0, 100.0);
    }
    
    double tempScore = 100.0;
    if (today.avgTemperatureC != null) {
      // Optimal temp is ~ 36.5C
      tempScore = (100.0 - (today.avgTemperatureC! - 36.5).abs() * 20).clamp(0.0, 100.0);
    }
    
    _pData = PhysiologicalData(
      heartRate: hrScore,
      hrv: hrvScore,
      bloodPressure: bpScore,
      spo2: spo2Score,
      skinTemperature: tempScore,
    );
    
    // --- Behavioral ---
    double sleepDurScore = 100.0;
    if (today.sleepMinutes != null) {
      // Optimal sleep is 8 hours (480 mins)
      sleepDurScore = (today.sleepMinutes! / 480.0 * 100.0).clamp(0.0, 100.0);
    }
    
    double sleepQualScore = sleepDurScore; 
    if (today.deepMinutes != null && today.sleepMinutes != null && today.sleepMinutes! > 0) {
      // Deep sleep should be around 20% of total sleep for optimal quality
      double deepPct = today.deepMinutes! / today.sleepMinutes!;
      sleepQualScore = (deepPct / 0.2 * 100.0).clamp(0.0, 100.0);
    }
    
    double activityScore = 100.0;
    if (today.steps != null) {
      // Optimal activity is 10k steps
      activityScore = (today.steps! / 10000.0 * 100.0).clamp(0.0, 100.0);
    }
    
    // Stress isn't natively provided by HealthConnectToday, so we derive it inversely from HRV.
    double stressScore = (100.0 - hrvScore).clamp(0.0, 100.0); 
    
    _rData = BehavioralData(
      sleepDuration: sleepDurScore,
      sleepQuality: sleepQualScore,
      dailyActivity: activityScore,
      workoutLoad: activityScore, // Derived proxy
      stress: stressScore, 
    );
    
    _recalculate();
  }

  void _startSensorListeners() {
    _accelSubscription = userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
      double magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      _lastMagnitude = magnitude;
      
      // Basic threshold check to avoid constant recalculation
      if (magnitude > 15.0) { 
        _recalculate();
      }
    });
  }

  void _recalculate() {
    // Determine impact based on magnitude
    double impact = (_lastMagnitude / 50.0) * 100;
    impact = impact.clamp(0.0, 100.0);
    
    MotionData mData = MotionData(
      impact: impact,
      orientation: 95, 
      recoveryAttempts: 100,
      fallHistory: 10, 
      accelerationMagnitude: _lastMagnitude,
    );

    _currentResult = _engine.calculateRisk(
      pData: _pData,
      rData: _rData,
      mData: mData,
      wData: _wData,
      context: _context,
    );
    
    notifyListeners();
  }

  @override
  void dispose() {
    _healthSyncTimer?.cancel();
    _accelSubscription?.cancel();
    super.dispose();
  }
}
