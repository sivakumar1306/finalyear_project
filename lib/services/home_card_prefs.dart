import 'package:shared_preferences/shared_preferences.dart';
import '../screens/home/home_screen.dart';

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

  static const _compactModeKey = 'home_card_compact_mode';

  /// Returns whether the user has enabled compact (small) card mode globally.
  static Future<bool> loadCompactMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_compactModeKey) ?? false;
  }

  static Future<void> saveCompactMode(bool compact) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_compactModeKey, compact);
  }
}
