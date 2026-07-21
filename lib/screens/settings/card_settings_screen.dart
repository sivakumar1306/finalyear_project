import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/home_card_prefs.dart';
import '../../theme/app_theme.dart';
import '../home/home_screen.dart'; // HomeCardId enum

/// Full-screen card visibility + reorder editor.
///
/// Figma label: "Goal setting"
/// Each row has:  drag-handle · label · gold on/off switch
/// Persists changes via [HomeCardPrefs].
class CardSettingsScreen extends StatefulWidget {
  const CardSettingsScreen({super.key});
  @override
  State<CardSettingsScreen> createState() => _CardSettingsScreenState();
}

class _CardSettingsScreenState extends State<CardSettingsScreen> {
  late List<HomeCardId> _order;
  late Set<HomeCardId> _hidden;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final order = await HomeCardPrefs.loadOrder();
    final hidden = await HomeCardPrefs.loadHidden();
    if (mounted) setState(() { _order = order; _hidden = hidden; _loaded = true; });
  }

  Future<void> _persist() async {
    await HomeCardPrefs.saveOrder(_order);
    await HomeCardPrefs.saveHidden(_hidden);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _label(HomeCardId id) {
    switch (id) {
      case HomeCardId.alarmActivity:
        return 'Alarm Activity';
      case HomeCardId.stress:
        return 'Stress';
      case HomeCardId.womensHealth:
        return "Women's Health";
      case HomeCardId.sleepHrv:
        return 'Sleep HRV';
      case HomeCardId.bloodOxygenHeartRate:
        return 'Blood Oxygen & Heart Rate';
      case HomeCardId.bloodPressure:
        return 'Blood Pressure';
    }
  }

  IconData _icon(HomeCardId id) {
    switch (id) {
      case HomeCardId.alarmActivity:
        return Icons.directions_run_rounded;
      case HomeCardId.stress:
        return Icons.psychology_rounded;
      case HomeCardId.womensHealth:
        return Icons.favorite_rounded;
      case HomeCardId.sleepHrv:
        return Icons.bedtime_rounded;
      case HomeCardId.bloodOxygenHeartRate:
        return Icons.monitor_heart_rounded;
      case HomeCardId.bloodPressure:
        return Icons.speed_rounded;
    }
  }

  Color _iconColor(HomeCardId id) {
    switch (id) {
      case HomeCardId.alarmActivity:
        return AppTheme.stepsColor;
      case HomeCardId.stress:
        return AppTheme.stressColor;
      case HomeCardId.womensHealth:
        return AppTheme.womenColor;
      case HomeCardId.sleepHrv:
        return AppTheme.sleepColor;
      case HomeCardId.bloodOxygenHeartRate:
        return AppTheme.spo2Color;
      case HomeCardId.bloodPressure:
        return AppTheme.bpColor;
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: _loaded ? _buildContent() : const Center(child: CircularProgressIndicator(color: AppTheme.gold)),
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAppBar(),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'SELECT CARDS TO DISPLAY',
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 4),
          Text(
            'Edit Cards',
            style: GoogleFonts.inter(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: ReorderableListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            proxyDecorator: _proxyDecorator,
            buildDefaultDragHandles: false,
            itemCount: _order.length,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex -= 1;
                final item = _order.removeAt(oldIndex);
                _order.insert(newIndex, item);
              });
              _persist();
            },
            itemBuilder: (context, index) {
              final id = _order[index];
              final isVisible = !_hidden.contains(id);
              final isLast = index == _order.length - 1;
              return _CardRow(
                key: ValueKey(id),
                index: index,
                label: _label(id),
                icon: _icon(id),
                iconColor: _iconColor(id),
                isVisible: isVisible,
                showDivider: !isLast,
                onToggle: (val) {
                  setState(() {
                    if (val) {
                      _hidden.remove(id);
                    } else {
                      _hidden.add(id);
                    }
                  });
                  _persist();
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _proxyDecorator(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final double elevation = Tween<double>(begin: 0, end: 8).evaluate(animation);
        return Material(
          color: Colors.transparent,
          elevation: elevation,
          shadowColor: Colors.black54,
          borderRadius: BorderRadius.circular(16),
          child: child,
        );
      },
      child: child,
    );
  }
}

/// A single row: drag-handle · icon · label · gold switch
class _CardRow extends StatelessWidget {
  final int index;
  final String label;
  final IconData icon;
  final Color iconColor;
  final bool isVisible;
  final bool showDivider;
  final ValueChanged<bool> onToggle;

  const _CardRow({
    required super.key,
    required this.index,
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.isVisible,
    required this.showDivider,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              // drag handle
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(Icons.drag_handle_rounded, color: Colors.white.withValues(alpha: 0.25), size: 22),
                ),
              ),
              // icon
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 12),
              // label
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    color: isVisible ? Colors.white : Colors.white.withValues(alpha: 0.35),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              // gold switch
              SizedBox(
                height: 28,
                child: Switch(
                  value: isVisible,
                  activeThumbColor: AppTheme.goldAccent,
                  activeTrackColor: AppTheme.goldAccent,
                  inactiveThumbColor: Colors.white.withValues(alpha: 0.5),
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.08),
                  trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
                  onChanged: onToggle,
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 0.5,
            indent: 56,
            endIndent: 12,
            color: Colors.white.withValues(alpha: 0.06),
          ),
      ],
    );
  }
}
