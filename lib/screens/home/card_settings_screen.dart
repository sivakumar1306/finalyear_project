import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/home_card_prefs.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_header.dart';
import '../../widgets/glass_icon_button.dart';
import 'home_screen.dart';

class _CardItem {
  final HomeCardId id;
  final String name;
  final Color color;
  final IconData icon;

  const _CardItem(this.id, this.name, this.color, this.icon);
}

const _kCardItems = [
  _CardItem(HomeCardId.alarms, 'Alarms', Color(0xFF6B82D9), Icons.notifications_outlined),
  _CardItem(HomeCardId.activity, 'Activity', Color(0xFFE08A4A), Icons.directions_walk),
  _CardItem(HomeCardId.stress, 'Stress', Color(0xFF6BC99B), Icons.water_drop),
  _CardItem(HomeCardId.womensHealth, "Women's Health", Color(0xFFD860C8), Icons.woman),
  _CardItem(HomeCardId.sleep, 'Sleep', Color(0xFF6B82D9), Icons.bedtime),
  _CardItem(HomeCardId.hrv, 'HRV', Color(0xFFC9A86E), Icons.favorite_border),
  _CardItem(HomeCardId.bloodOxygen, 'Blood Oxygen', Color(0xFF73D4F8), Icons.air),
  _CardItem(HomeCardId.heartRate, 'Heart Rate', Color(0xFFC96B6B), Icons.favorite),
  _CardItem(HomeCardId.bloodPressure, 'Blood Pressure', Color(0xFFD86560), Icons.speed),
  _CardItem(HomeCardId.temperature, 'Temperature', Color(0xFFE3B76A), Icons.device_thermostat),
];

class CardSettingsScreen extends StatefulWidget {
  final VoidCallback? onClose;
  const CardSettingsScreen({super.key, this.onClose});

  @override
  State<CardSettingsScreen> createState() => _CardSettingsScreenState();
}

class _CardSettingsScreenState extends State<CardSettingsScreen> {
  late List<HomeCardId> _order;
  late Set<HomeCardId> _hidden;
  late Set<HomeCardId> _expanded;
  bool _compactMode = false;
  bool _loaded = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final order = await HomeCardPrefs.loadOrder();
    final hidden = await HomeCardPrefs.loadHidden();
    final expanded = await HomeCardPrefs.loadExpanded();
    final compactMode = await HomeCardPrefs.loadCompactMode();
    if (mounted) {
      setState(() {
        _order = order;
        _hidden = hidden;
        _expanded = expanded;
        _compactMode = compactMode;
        _loaded = true;
      });
    }
  }

  Future<void> _save() async {
    await HomeCardPrefs.saveOrder(_order);
    await HomeCardPrefs.saveHidden(_hidden);
    await HomeCardPrefs.saveExpanded(_expanded);
    await HomeCardPrefs.saveCompactMode(_compactMode);
  }

  /// Saves pending changes (if any) and leaves the screen — either via the
  /// optional [onClose] callback (embedded use) or by popping the route.
  void _finish() {
    if (_changed) _save();
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.pop(context);
    }
  }

  bool _isVisible(HomeCardId id) => !_hidden.contains(id);
  bool _isExpanded(HomeCardId id) => _expanded.contains(id);

  void _toggleVisibility(HomeCardId id) {
    setState(() {
      if (_hidden.contains(id)) {
        _hidden.remove(id);
      } else {
        _hidden.add(id);
      }
      _changed = true;
    });
  }

  void _toggleExpanded(HomeCardId id) {
    setState(() {
      if (_expanded.contains(id)) {
        _expanded.remove(id);
      } else {
        _expanded.add(id);
      }
      _changed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        backgroundColor: Color(0xFF050505),
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final visibleItems = _kCardItems.where((item) => _order.contains(item.id)).toList()
      ..sort((a, b) => _order.indexOf(a.id).compareTo(_order.indexOf(b.id)));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _finish();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF050505),
        body: SafeArea(
          child: Column(
            children: [
              GlassHeader(
                title: 'Edit Cards',
                onBack: _finish,
                trailing: GlassIconButton(
                  icon: Icons.check_rounded,
                  onTap: _finish,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 18, 28, 12),
                child: Stack(
                  children: [
                    Center(
                      child: Text(
                        'SELECT CARDS TO DISPLAY',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.42),
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _compactMode = !_compactMode;
                            _changed = true;
                          });
                        },
                        child: Row(
                          children: [
                            Text(
                              'Compact',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: _compactMode ? AppTheme.gold : Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Transform.scale(
                              scale: 0.55,
                              child: CupertinoSwitch(
                                value: _compactMode,
                                activeTrackColor: AppTheme.gold,
                                inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                                onChanged: (v) {
                                  setState(() {
                                    _compactMode = v;
                                    _changed = true;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
                        ),
                        child: ReorderableListView.builder(
                          itemCount: visibleItems.length,
                          onReorderItem: (int oldIndex, int newIndex) {
                            setState(() {
                              final item = _order.removeAt(oldIndex);
                              _order.insert(newIndex, item);
                              _changed = true;
                            });
                          },
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                          itemBuilder: (context, index) {
                            final item = visibleItems[index];
                            return _CardSettingsRow(
                              key: ValueKey(item.id),
                              item: item,
                              visible: _isVisible(item.id),
                              expanded: _isExpanded(item.id),
                              onToggleVisibility: () => _toggleVisibility(item.id),
                              onToggleExpanded: () => _toggleExpanded(item.id),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardSettingsRow extends StatelessWidget {
  final _CardItem item;
  final bool visible;
  final bool expanded;
  final VoidCallback onToggleVisibility;
  final VoidCallback onToggleExpanded;

  const _CardSettingsRow({
    super.key,
    required this.item,
    required this.visible,
    required this.expanded,
    required this.onToggleVisibility,
    required this.onToggleExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final dimmed = !visible;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x0AFFFFFF), width: 0.5)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.format_list_bulleted_rounded,
            size: 24,
            color: Colors.white.withValues(alpha: dimmed ? 0.25 : 0.7),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              item.name,
              style: GoogleFonts.inter(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: dimmed
                    ? Colors.white.withValues(alpha: 0.35)
                    : Colors.white.withValues(alpha: 0.92),
              ),
            ),
          ),
          if (visible)
            GestureDetector(
              onTap: onToggleExpanded,
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                child: Icon(
                  expanded ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                  size: 18,
                  color: expanded ? item.color : Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ),
          Transform.scale(
            scale: 0.7,
            child: CupertinoSwitch(
              value: visible,
              activeTrackColor: AppTheme.gold,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
              onChanged: (_) => onToggleVisibility(),
            ),
          ),
        ],
      ),
    );
  }
}
