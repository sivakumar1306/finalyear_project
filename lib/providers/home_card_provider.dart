import 'package:flutter/foundation.dart';
import '../screens/home/home_card_id.dart';
import '../services/home_card_prefs.dart';

class HomeCardProvider extends ChangeNotifier {
  List<HomeCardId> _order = List.of(HomeCardId.values);
  Set<HomeCardId> _hiddenCards = {};
  Set<HomeCardId> _expandedCards = {};
  bool _compactMode = false;
  bool _isLoaded = false;

  List<HomeCardId> get order => List.unmodifiable(_order);
  Set<HomeCardId> get hiddenCards => Set.unmodifiable(_hiddenCards);
  Set<HomeCardId> get expandedCards => Set.unmodifiable(_expandedCards);
  bool get compactMode => _compactMode;
  bool get isLoaded => _isLoaded;

  Future<void> load() async {
    final order = await HomeCardPrefs.loadOrder();
    final hidden = await HomeCardPrefs.loadHidden();
    final expanded = await HomeCardPrefs.loadExpanded();
    final compactMode = await HomeCardPrefs.loadCompactMode();

    _order = order;
    _hiddenCards = hidden;
    _expandedCards = expanded;
    _compactMode = compactMode;
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setOrder(List<HomeCardId> newOrder) async {
    _order = List.of(newOrder);
    notifyListeners();
    await HomeCardPrefs.saveOrder(_order);
  }

  Future<void> toggleVisibility(HomeCardId id) async {
    final newHidden = Set<HomeCardId>.from(_hiddenCards);
    if (newHidden.contains(id)) {
      newHidden.remove(id);
    } else {
      newHidden.add(id);
    }
    _hiddenCards = newHidden;
    notifyListeners();
    await HomeCardPrefs.saveHidden(_hiddenCards);
  }

  Future<void> toggleExpanded(HomeCardId id) async {
    final newExpanded = Set<HomeCardId>.from(_expandedCards);
    if (newExpanded.contains(id)) {
      newExpanded.remove(id);
    } else {
      newExpanded.add(id);
    }
    _expandedCards = newExpanded;
    notifyListeners();
    await HomeCardPrefs.saveExpanded(_expandedCards);
  }

  Future<void> setCompactMode(bool compact) async {
    _compactMode = compact;
    notifyListeners();
    await HomeCardPrefs.saveCompactMode(_compactMode);
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final newOrder = List<HomeCardId>.from(_order);
    final item = newOrder.removeAt(oldIndex);
    newOrder.insert(newIndex, item);
    _order = newOrder;
    notifyListeners();
    await HomeCardPrefs.saveOrder(_order);
  }

  void ensureWomensHealthVisible(bool isFemale) {
    if (isFemale && !_order.contains(HomeCardId.womensHealth)) {
      final newOrder = List<HomeCardId>.from(_order);
      if (newOrder.length >= 2) {
        newOrder.insert(2, HomeCardId.womensHealth);
      } else {
        newOrder.add(HomeCardId.womensHealth);
      }
      _order = newOrder;
      notifyListeners();
      HomeCardPrefs.saveOrder(_order);
    }
  }
}
