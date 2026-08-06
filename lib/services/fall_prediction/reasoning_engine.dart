import '../../models/fall_prediction/layer_inputs.dart';

class ReasoningEngine {
  static List<String> generateReasoningChain(
    double currentHsi,
    Layer1PhysiologyData pData,
    Layer2RecoveryData rData,
    Layer3MotionData mData,
  ) {
    List<String> chain = ['HSI: ${currentHsi.toStringAsFixed(0)}'];
    
    // Calculate deviations (assuming 100 is optimal)
    // Deviation = 100 - score
    Map<String, double> deviations = {
      'Heart Rate': 100 - (pData.hr ?? 100.0),
      'HRV': 100 - (pData.hrv ?? 100.0),
      'Sleep Duration': 100 - (rData.slp ?? 100.0),
      'Sleep Quality': 100 - (rData.slq ?? 100.0),
      'Motion Stability (Gait)': 100 - (mData.gait ?? 100.0), // High gait stability is good
      'Postural Sway': mData.psw ?? 0.0, // High sway is bad
      'Stress': rData.str ?? 0.0, // High stress is bad
    };
    
    // Sort by magnitude of negative deviation (highest first)
    var sortedEntries = deviations.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
      
    // Filter and take top 2 most severely degraded metrics
    var topIssues = sortedEntries.where((e) => e.value > 10).take(2).toList();
    
    if (topIssues.isEmpty) {
      chain.add('Metrics stable. Keep up the good work.');
      return chain;
    }
    
    for (var issue in topIssues) {
      if (issue.key.contains('Sleep')) {
        chain.add('Driven by severe sleep debt (${issue.key.toLowerCase()})');
      } else if (issue.key.contains('Motion') || issue.key.contains('Sway')) {
        chain.add('Motion stability reduced by ${issue.value.toStringAsFixed(0)}%');
      } else if (issue.key == 'Stress') {
        chain.add('High stress levels impacting recovery');
      } else {
        chain.add('${issue.key} degraded by ${issue.value.toStringAsFixed(0)}%');
      }
    }
    
    // Add Recommendation
    if (topIssues.any((e) => e.key.contains('Motion') || e.key.contains('Sway'))) {
      chain.add('Recommendation: Avoid stairs and high-strain activity.');
    } else if (topIssues.any((e) => e.key.contains('Sleep'))) {
      chain.add('Recommendation: Prioritize rest and recovery today.');
    } else {
      chain.add('Recommendation: Monitor vitals closely.');
    }
    
    return chain;
  }
}
