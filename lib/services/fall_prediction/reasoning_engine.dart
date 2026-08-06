import '../../models/fall_prediction/physiological_data.dart';
import '../../models/fall_prediction/behavioral_data.dart';
import '../../models/fall_prediction/motion_data.dart';

/// Builds a deterministic reasoning chain from normalized 0–100 metric scores.
/// Higher is better for HR/HRV/sleep/orientation; higher is worse for impact/stress.
class ReasoningEngine {
  static const double optimalBaseline = 100.0;
  static const double issueThreshold = 10.0;

  static List<String> generateReasoningChain(
    double currentHsi,
    PhysiologicalData pData,
    BehavioralData rData,
    MotionData mData,
  ) {
    List<String> chain = ['HSI: ${currentHsi.toStringAsFixed(0)}'];

    Map<String, double> deviations = {
      'Heart Rate': optimalBaseline - pData.heartRate,
      'HRV': optimalBaseline - pData.hrv,
      'Sleep Duration': optimalBaseline - rData.sleepDuration,
      'Sleep Quality': optimalBaseline - rData.sleepQuality,
      'Motion Stability (Orientation)': optimalBaseline - mData.orientation,
      'Impact': mData.impact,
      'Stress': rData.stress,
    };
    
    // Sort by magnitude of negative deviation (highest first)
    var sortedEntries = deviations.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
      
    // Filter and take top 2 most severely degraded metrics
    var topIssues =
        sortedEntries.where((e) => e.value > issueThreshold).take(2).toList();
    
    if (topIssues.isEmpty) {
      chain.add('Metrics stable. Keep up the good work.');
      return chain;
    }
    
    for (var issue in topIssues) {
      if (issue.key.contains('Sleep')) {
        chain.add('Driven by severe sleep debt (${issue.key.toLowerCase()})');
      } else if (issue.key.contains('Motion') || issue.key.contains('Impact')) {
        chain.add('Motion stability reduced by ${issue.value.toStringAsFixed(0)}%');
      } else if (issue.key == 'Stress') {
        chain.add('High stress levels impacting recovery');
      } else {
        chain.add('${issue.key} degraded by ${issue.value.toStringAsFixed(0)}%');
      }
    }
    
    // Add Recommendation
    if (topIssues.any((e) => e.key.contains('Motion') || e.key.contains('Impact'))) {
      chain.add('Recommendation: Avoid stairs and high-strain activity.');
    } else if (topIssues.any((e) => e.key.contains('Sleep'))) {
      chain.add('Recommendation: Prioritize rest and recovery today.');
    } else {
      chain.add('Recommendation: Monitor vitals closely.');
    }
    
    return chain;
  }
}
