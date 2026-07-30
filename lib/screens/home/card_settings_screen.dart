import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/home_card_prefs.dart';
import '../../theme/app_theme.dart';

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
  _CardItem(HomeCardId.sleep, 'Sleep', Color(0xFF6B82D9), Icons.bedtime),
  _CardItem(HomeCardId.hrv, 'HRV', Color(0xFFC9A86E), Icons.favorite_border),
  _CardItem(HomeCardId.bloodOxygen, 'Blood Oxygen', Color(0xFF73D4F8), Icons.air),
  _CardItem(HomeCardId.heartRate, 'Heart Rate', Color(0xFFC96B6B), Icons.favorite),
  _CardItem(HomeCardId.sports, 'Sports', Color(0xFFE08A4A), Icons.fitness_center),
  _CardItem(HomeCardId.womensHealth, "Women's Health", Color(0xFFD860C8), Icons.woman),
  _CardItem(HomeCardId.temperature, 'Temperature', Color(0xFFE3B76A), Icons.device_thermostat),
  _CardItem(HomeCardId.bloodPressure, 'Blood Pressure', Color(0xFFD86560), Icons.speed),
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
  late Set<HomeCardId> _compact;
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
    final compact = await HomeCardPrefs.loadCompact();
    if (mounted) {
      setState(() {
        _order = order;
        _hidden = hidden;
        _compact = compact;
        _loaded = true;
      });
    }
  }

  Future<void> _save() async {
    await HomeCardPrefs.saveOrder(_order);
    await HomeCardPrefs.saveHidden(_hidden);
    await HomeCardPrefs.saveCompact(_compact);
  }

  bool _isVisible(HomeCardId id) => !_hidden.contains(id);
  bool _isCompact(HomeCardId id) => _compact.contains(id);

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

  void _toggleCompact(HomeCardId id) {
    setState(() {
      if (_compact.contains(id)) {
        _compact.remove(id);
      } else {
        _compact.add(id);
      }
      _changed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    final visibleItems = _kCardItems.where((item) => _order.contains(item.id)).toList()
      ..sort((a, b) => _order.indexOf(a.id).compareTo(_order.indexOf(b.id)));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_changed) _save();
        widget.onClose?.call();
      },
      child: Column(
        children: [
          const SizedBox(height: 44),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _GlassCircleButton(
                  icon: Icons.chevron_left,
                  onTap: () {
                    if (_changed) _save();
                    widget.onClose?.call();
                  },
                ),
                const Spacer(),
                Text(
                  'Edit Cards',
                  style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white),
                ),
                const Spacer(),
                _GlassCircleButton(
                  icon: Icons.check,
                  onTap: () {
                    if (_changed) _save();
                    widget.onClose?.call();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Text(
                  'SELECT CARDS TO DISPLAY',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.gold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              itemCount: visibleItems.length,
              onReorderItem: (int oldIndex, int newIndex) {
                setState(() {
                  final item = _order.removeAt(oldIndex);
                  _order.insert(newIndex, item);
                  _changed = true;
                });
              },
              padding: EdgeInsets.zero,
              itemBuilder: (context, index) {
                final item = visibleItems[index];
                return _CardSettingsRow(
                  key: ValueKey(item.id),
                  item: item,
                  visible: _isVisible(item.id),
                  compact: _isCompact(item.id),
                  index: index,
                  onToggleVisibility: () => _toggleVisibility(item.id),
                  onToggleCompact: () => _toggleCompact(item.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CardSettingsRow extends StatelessWidget {
  final _CardItem item;
  final bool visible;
  final bool compact;
  final int index;
  final VoidCallback onToggleVisibility;
  final VoidCallback onToggleCompact;

  const _CardSettingsRow({
    super.key,
    required this.item,
    required this.visible,
    required this.compact,
    required this.index,
    required this.onToggleVisibility,
    required this.onToggleCompact,
  });

  @override
  Widget build(BuildContext context) {
    final dimmed = !visible;
    return Container(
      height: 48,
      padding: const EdgeInsets.only(right: 6),

      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1A1A1A), width: 0.5)),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Container(
              width: 40,
              height: 48,
              alignment: Alignment.center,
              child: Icon(Icons.drag_handle, color: Colors.white.withValues(alpha: dimmed ? 0.1 : 0.25), size: 20),
            ),
          ),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: visible ? item.color.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(item.icon, size: 14, color: visible ? item.color : const Color(0xFF666666)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              item.name,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: dimmed ? Colors.white.withValues(alpha: 0.35) : Colors.white,
              ),
            ),
          ),
          if (visible)
            GestureDetector(
              onTap: onToggleCompact,
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                child: Icon(
                  compact ? Icons.grid_view_rounded : Icons.fullscreen_rounded,
                  size: 18,
                  color: compact ? item.color : Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ),
          Transform.scale(
            scale: 0.65,
            child: CupertinoSwitch(
              value: visible,
              activeTrackColor: item.color,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
              onChanged: (_) => onToggleVisibility(),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _GlassCircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 0.5),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
