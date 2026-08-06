import 'package:flutter/material.dart';
import '../../models/fall_prediction/layer_inputs.dart';
import 'fall_risk_registry.dart';

class RefinedOvulationDate {
  final DateTime date;
  final double? confidence;

  RefinedOvulationDate({
    required this.date,
    this.confidence,
  });
}

class CycleDates {
  final DateTime ovulationDate;
  final DateTime nextPeriod;
  final DateTimeRange fertileWindow;

  CycleDates({
    required this.ovulationDate,
    required this.nextPeriod,
    required this.fertileWindow,
  });
}

class Layer4WomensHealthCalculator {
  /// 1. Implement Privacy and Edge-Case Gates
  /// If [hasConsentedToWomensHealth] is false, or [CycleState] is postMenopause, 
  /// preMenarche, or optedOut, the layer must immediately return a null or neutral 
  /// [WomensHealthScore]. The downstream HSI engine must catch this, set its context 
  /// factor (C_i) to 1 (neutral), and renormalize the remaining alpha/beta/gamma 
  /// weights without the WH delta weight.
  static WomensHealthScore? calculateScore(Layer4WomensHealthData data, {DateTime? currentLpDate}) {
    if (!data.hasConsentedToWomensHealth) {
      return null;
    }

    if (data.cycleState == CycleState.postMenopause ||
        data.cycleState == CycleState.preMenarche ||
        data.cycleState == CycleState.optedOut) {
      return null;
    }

    // Default score computation for active / hormonalContraception states.
    // Higher score = lower hormonal-phase contribution to instability (better stability).
    double score = 100.0;
    
    if (data.isPMS) {
      score = 80.0; // Reduce score during PMS as a basic heuristic
    }

    return WomensHealthScore(score.clamp(0.0, 100.0), confidence: 1.0);
  }

  /// 2. Implement Calendar-Based Date Math
  static CycleDates calculateCycleDates(DateTime lpDate, int cycleLength) {
    // ovulationDate (OD) = lpDate + (cycleLength - 14) days
    final ovulationDate = lpDate.add(Duration(days: cycleLength - 14));
    
    // nextPeriod (NP) = lpDate + cycleLength days
    final nextPeriod = lpDate.add(Duration(days: cycleLength));
    
    // fertileWindow (FW) = OD - 5 days to OD + 1 day
    final fertileWindow = DateTimeRange(
      start: ovulationDate.subtract(const Duration(days: 5)),
      end: ovulationDate.add(const Duration(days: 1)),
    );

    return CycleDates(
      ovulationDate: ovulationDate,
      nextPeriod: nextPeriod,
      fertileWindow: fertileWindow,
    );
  }

  /// 3. Implement Wearable-Derived Refinement
  static RefinedOvulationDate refineOvulationDate(
    DateTime calendarOd,
    double tempTrend,
    double hrvTrend,
    double slpTrend,
    CycleState state,
  ) {
    // Logic Gate: Bypass wearable refinement for hormonal contraception
    if (state == CycleState.hormonalContraception) {
      return RefinedOvulationDate(
        date: calendarOd,
        confidence: null, // Drop confidence score
      );
    }

    // For active states, adjust calendarOd forward or backward based on
    // luteal-phase baseline deviations in TEMP, HRV, and SLP to flag anovulatory 
    // or irregular cycles.
    int daysAdjustment = 0;
    double confidenceAdjustment = 1.0;

    // Example refinement heuristics:
    // If tempTrend is significantly higher than baseline earlier than expected, ovulation might be early.
    // If tempTrend remains low, ovulation might be delayed (anovulatory/irregular flag).
    if (tempTrend > 0.3 && hrvTrend < -0.1) {
      daysAdjustment = -1; // Early
      confidenceAdjustment = 0.9;
    } else if (tempTrend < -0.3) {
      daysAdjustment = 2; // Delayed or potentially anovulatory flag
      confidenceAdjustment = 0.7; 
    }

    // Additional refinement using sleep trend
    if (slpTrend < -0.2) {
      // Sleep disturbances might further reduce confidence in the exact date
      confidenceAdjustment -= 0.1;
    }

    return RefinedOvulationDate(
      date: calendarOd.add(Duration(days: daysAdjustment)),
      confidence: confidenceAdjustment.clamp(0.0, 1.0),
    );
  }
}
