enum FallRiskSymbol {
  // Layer 1 Outputs
  p, // Physiological Stability Score
  
  // Layer 2 Outputs
  rc, // Recovery Score
  
  // Layer 3 Outputs
  mo, // Motion Stability Score
  
  // Layer 4 Outputs
  wh, // Women's Health Adjustment Score
  
  // Final Outputs
  hsiBase,
  hsiAdj,
  frs,
  tau, // Prediction horizon
  q,   // Coverage/confidence score
}

class PhysiologicalScore {
  final double value;
  
  PhysiologicalScore(this.value) {
    assert(value >= 0.0 && value <= 100.0, 'Score must be between 0 and 100');
  }
}

class RecoveryScore {
  final double value;
  
  RecoveryScore(this.value) {
    assert(value >= 0.0 && value <= 100.0, 'Score must be between 0 and 100');
  }
}

class MotionStabilityScore {
  final double value;
  
  MotionStabilityScore(this.value) {
    assert(value >= 0.0 && value <= 100.0, 'Score must be between 0 and 100');
  }
}

/// STRICT ARCHITECTURAL ROUTING (FRS v2 Spec):
/// The [WomensHealthScore] output strictly returns a value between 0-100
/// (where higher = lower hormonal-phase contribution to instability).
/// 
/// IMPORTANT: 
/// This score is ONLY to be injected into the Health Stability Index (HSI) 
/// calculation module, or used as a Context Factor for Layers 2 and 3.
/// The FRS (Fall Risk Score) calculation class MUST NOT accept [WomensHealthScore] 
/// directly, completely severing the direct link to fall incidence as per the v2 specification.
class WomensHealthScore {
  final double value;
  final double? confidence;
  
  WomensHealthScore(this.value, {this.confidence}) {
    assert(value >= 0.0 && value <= 100.0, 'Score must be between 0 and 100');
  }
}
