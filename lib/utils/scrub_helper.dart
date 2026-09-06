/// Pure scrub helper — no Widget.
abstract class ScrubHelper {
  static int initialIndex(List<int> values) {
    for (int i = values.length - 1; i >= 0; i--) {
      if (values[i] > 0) return i;
    }
    return 0;
  }

  static int initialIndexDouble(List<double> values) {
    for (int i = values.length - 1; i >= 0; i--) {
      if (values[i] > 0) return i;
    }
    return 0;
  }

  static int indexFromDx(double dx, double width, int count) {
    if (count <= 0 || width <= 0) return 0;
    final slotW = width / count;
    int idx = (dx / slotW).floor();
    return idx.clamp(0, count - 1);
  }
}
