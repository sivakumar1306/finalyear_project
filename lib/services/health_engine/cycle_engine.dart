/// Pure cycle phase logic — extracted from home_vitals_cards / home_compact_cards
class CycleEngine {
  static String phaseName(int cycleDay, int periodLen, int cycleLength) {
    if (cycleDay <= 0) return '---';
    if (cycleDay <= periodLen) return 'Menstruation';
    if (cycleDay <= 13) return 'Follicular';
    if (cycleDay <= 16) return 'Ovulating';
    return 'Luteal';
  }

  static int cycleDay(DateTime periodStart, DateTime now) {
    final start = DateTime(periodStart.year, periodStart.month, periodStart.day);
    final cur = DateTime(now.year, now.month, now.day);
    return cur.difference(start).inDays + 1;
  }

  // Flex ratios for CyclePhaseBar
  static ({int pLen, int fol, int ov, int lut}) flexes(int cycleLength, int periodLen) {
    final len = cycleLength > 0 ? cycleLength : 28;
    final pLen = periodLen > 0 ? periodLen : 5;
    final fol = (13 - pLen).clamp(1, len);
    const ov = 3;
    final lut = (len - 16).clamp(1, len);
    return (pLen: pLen, fol: fol, ov: ov, lut: lut);
  }
}
