import 'package:shared_preferences/shared_preferences.dart';

enum HomeCardId {
  alarms,
  activity,
  stress,
  sleep,
  hrv,
  bloodOxygen,
  heartRate,
  sports,
  womensHealth,
  temperature,
  bloodPressure,
}

/// Centralised persistence for the home dashboard's card order and visibility.
///
/// Both the inline drag-reorder editor on the Home screen and the full-screen
/// "Edit Cards" screen (CardSettingsScreen) read/write through this class so
/// they stay in sync without duplicating key names or loading logic.
class HomeCardPrefs {
  static const _orderKey = 'home_card_order';
  static const _hiddenKey = 'home_card_visibility';

  // ── Order ──────────────────────────────────────────────────────────────────

  /// Returns the persisted card order, back-filled with any enum values that
  /// were added since the user last saved (so new cards appear at the end
  /// rather than vanishing).
  static Future<List<HomeCardId>> loadOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_orderKey);
    if (saved == null || saved.isEmpty) return List.of(HomeCardId.values);

    final List<HomeCardId> order = [];
    for (final name in saved) {
      try {
        order.add(HomeCardId.values.byName(name));
      } catch (_) {
        // ignore invalid/deprecated names
      }
    }
    // Back-fill any new enum values not yet in the persisted list.
    for (final id in HomeCardId.values) {
      if (!order.contains(id)) order.add(id);
    }
    return order;
  }

  static Future<void> saveOrder(List<HomeCardId> order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_orderKey, order.map((e) => e.name).toList());
  }

  // ── Visibility ─────────────────────────────────────────────────────────────

  /// Returns the set of cards the user has explicitly hidden.  Absent from
  /// this set → visible (so new card types added in the future default to
  /// visible without a migration).
  static Future<Set<HomeCardId>> loadHidden() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_hiddenKey) ?? [];
    final Set<HomeCardId> hidden = {};
    for (final name in list) {
      try {
        hidden.add(HomeCardId.values.byName(name));
      } catch (_) {}
    }
    return hidden;
  }

  static Future<void> saveHidden(Set<HomeCardId> hidden) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_hiddenKey, hidden.map((e) => e.name).toList());
  }

  // ── Compact mode ────────────────────────────────────────────────────────────

  static const _compactKey = 'home_card_compact';

  /// Returns the set of cards the user has set to compact (small) mode.
  /// Cards not in this set are shown in expanded (big) mode.
  static Future<Set<HomeCardId>> loadCompact() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_compactKey) ?? [];
    final Set<HomeCardId> compact = {};
    for (final name in list) {
      try {
        compact.add(HomeCardId.values.byName(name));
      } catch (_) {}
    }
    return compact;
  }

  static Future<void> saveCompact(Set<HomeCardId> compact) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_compactKey, compact.map((e) => e.name).toList());
  }
}
