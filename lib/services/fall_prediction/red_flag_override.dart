import '../../models/fall_prediction/layer_inputs.dart';
import 'layer1_physiology.dart'; // For BpSource

enum EscalationLadder {
  t0ToT120s,
}

abstract class EscalationService {
  void triggerAlert({required EscalationLadder ladder, required String reason});
}

enum CorroborationSource {
  spO2,
}

abstract class CorroborationService {
  Future<bool> verifyDualSource(CorroborationSource source);
}

class RedFlagEmergencyException implements Exception {
  final String message;
  RedFlagEmergencyException(this.message);

  @override
  String toString() => 'RedFlagEmergencyException: $message';
}

class RedFlagOverrideService {
  Future<bool> checkCriticalThresholds({
    required Layer1PhysiologyData physiology,
    required Layer3MotionData motion,
    required EscalationService escalationService,
    required CorroborationService corroborationService,
  }) async {
    // 1. SpO2 < 90: MUST be gated by corroborationService.verifyDualSource(SpO2)
    if (physiology.spo2 != null && physiology.spo2! < 90.0) {
      bool isCorroborated = await corroborationService.verifyDualSource(CorroborationSource.spO2);
      if (isCorroborated) {
        escalationService.triggerAlert(
          ladder: EscalationLadder.t0ToT120s,
          reason: 'Critical SpO2 threshold breached and corroborated: ${physiology.spo2}',
        );
        return true;
      }
    }

    // 2. HR outside [40, 150]: Must check the HR time-series buffer to ensure this condition has been sustained for > 60 seconds
    if (physiology.hr != null && (physiology.hr! < 40.0 || physiology.hr! > 150.0)) {
      if (physiology.hrBuffer != null && physiology.hrBuffer!.isNotEmpty) {
        bool sustained = physiology.hrBuffer!.every((hr) => hr < 40.0 || hr > 150.0);
        if (sustained) {
          escalationService.triggerAlert(
            ladder: EscalationLadder.t0ToT120s,
            reason: 'Critical HR threshold sustained: ${physiology.hr}',
          );
          return true;
        }
      }
    }

    // 3. BP Emergency: Check if physiology.bpSource is hospitalBaseline or homeCuff (cleared)
    if (physiology.bpSource == BpSource.hospitalBaseline || physiology.bpSource == BpSource.homeCuff) {
      // Evaluate against clinically defined emergency ranges (e.g., Systolic > 180 or Diastolic > 120)
      if (physiology.sys != null && physiology.dia != null) {
        if (physiology.sys! > 180.0 || physiology.dia! > 120.0) {
          escalationService.triggerAlert(
            ladder: EscalationLadder.t0ToT120s,
            reason: 'Critical BP emergency threshold breached: ${physiology.sys}/${physiology.dia}',
          );
          return true;
        }
      }
    }

    // 4. ORTHO Drop: Evaluate motion.ortho against a validated orthostatic drop threshold
    if (motion.ortho != null && motion.ortho! >= 20.0) { // Using standard consensus definition: systolic drop >= 20 mmHg
      escalationService.triggerAlert(
        ladder: EscalationLadder.t0ToT120s,
        reason: 'Critical Orthostatic drop threshold breached: ${motion.ortho} (>= 20 mmHg)',
      );
      return true;
    }

    return false;
  }
}
