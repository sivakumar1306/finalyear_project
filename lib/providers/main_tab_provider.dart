import 'package:flutter/foundation.dart';

/// Lets a descendant far from MainShell (e.g. a Settings row) switch the
/// app's bottom-nav tab without pushing a duplicate route on top of it.
class MainTabProvider extends ChangeNotifier {
  int _tab = 0;
  int get tab => _tab;

  void setTab(int index) {
    if (_tab == index) return;
    _tab = index;
    notifyListeners();
  }
}
