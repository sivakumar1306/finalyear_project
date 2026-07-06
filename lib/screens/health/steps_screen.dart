import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/supabase_service.dart';


// ── Design tokens ───────────────────────────────────────────────────────────
const _kBg         = Color(0xFF050505);
const _kStepsColor = Color(0xFF4ADE80);
const _kDistColor  = Color(0xFF60A5FA);
const _kCalColor   = Color(0xFFFB923C);

const List<String> _monthAbbr = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

TextStyle _t(double s,
    {FontWeight w = FontWeight.w400, Color? c, double? ls}) =>
    GoogleFonts.inter(
      fontSize: s,
      fontWeight: w,
      color: c ?? Colors.white.withValues(alpha: 0.95),
      letterSpacing: ls,
    );

BoxDecoration _glass({double r = 20}) => BoxDecoration(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(r),
      border:
          Border.all(color: Colors.white.withValues(alpha: 0.09), width: 0.5),
    );

Widget _circleIconButton({required Widget icon, required VoidCallback onTap}) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
        child: Center(child: icon),
      ),
    );

// ══════════════════════════════════════════════════════════════════════════════

class StepsScreen extends StatefulWidget {
  const StepsScreen({super.key});
  @override
  State<StepsScreen> createState() => _StepsScreenState();
}

class _StepsScreenState extends State<StepsScreen> {
  final _ble = BleService();

  bool _dayLoad = false;

  DateTime _selectedDate = DateTime.now();

  // Today's totals from ring (cached so switching back to today is instant)
  int    _totalSteps = 0;
  int    _totalCal   = 0;
  double _totalDistM = 0.0;

  // The currently displayed day's values (may be a past day loaded from Supabase)
  int    _daySteps = 0;
  int    _dayCal   = 0;
  double _dayDistM = 0.0;

  // 96-slot 15-min intervals for today's bar charts (only populated for today)
  List<int>    _stepsSlots = List.filled(96, 0);
  List<int>    _calSlots   = List.filled(96, 0);
  List<double> _distSlots  = List.filled(96, 0.0);

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final ble = context.read<BleProvider>();
    if (ble.todaySteps > 0) {
      setState(() {
        _totalSteps = ble.todaySteps;
        _totalCal   = ble.todayCalories;
        _totalDistM = ble.todayDistanceM;
        _daySteps   = ble.todaySteps;
        _dayCal     = ble.todayCalories;
        _dayDistM   = ble.todayDistanceM;
        _stepsSlots = List<int>.from(ble.todayStepsByInterval);
      });
    }
    await _syncFromRing();
  }

  // ── Ring sync (today only) ────────────────────────────────────────────────

  Future<void> _syncFromRing() async {
    if (_dayLoad || !mounted) return;
    setState(() => _dayLoad = true);
    try {
      final json = await _ble.getTodaySteps();
      if (mounted) _parseRingData(json);
    } catch (_) {}
    if (mounted) setState(() => _dayLoad = false);
  }

  void _parseRingData(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      final list    = decoded is List ? decoded : <dynamic>[];

      final stepSlots = List<int>.filled(96, 0);
      final calSlots  = List<int>.filled(96, 0);
      final distSlots = List<double>.filled(96, 0.0);
      int totalSteps = 0, totalCal = 0;
      double totalDist = 0.0;

      for (final item in list) {
        final m     = item as Map<String, dynamic>;
        final d     = (m['d'] as num? ?? 0).toInt();
        final steps = (m['f'] as num? ?? 0).toInt();
        final cal   = (m['e'] as num? ?? 0).toInt() ~/ 1000;
        final dist  = (m['g'] as num? ?? 0).toDouble();
        totalSteps += steps;
        totalCal   += cal;
        totalDist  += dist;
        if (d >= 0 && d < 96) {
          stepSlots[d] += steps;
          calSlots[d]  += cal;
          distSlots[d] += dist;
        }
      }

      if (!mounted) return;
      setState(() {
        _totalSteps = totalSteps;
        _totalCal   = totalCal;
        _totalDistM = totalDist;
        if (_isToday(_selectedDate)) {
          _daySteps   = totalSteps;
          _dayCal     = totalCal;
          _dayDistM   = totalDist;
          _stepsSlots = stepSlots;
          _calSlots   = calSlots;
          _distSlots  = distSlots;
        }
      });
      context.read<BleProvider>().updateStepsData(
          totalSteps, totalCal, totalDist, stepSlots);
      _saveToDb(totalSteps, totalCal, totalDist);
    } catch (_) {}
  }

  Future<void> _saveToDb(int steps, int cal, double dist) async {
    if (steps <= 0 && cal <= 0) return;
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      await SupabaseService.upsertSteps(
          userId: user.id,
          date: DateTime.now(),
          steps: steps,
          calories: cal,
          distanceM: dist);
    } catch (_) {}
  }

  // ── Past-day Supabase lookup ──────────────────────────────────────────────

  Future<void> _loadPastDayData(DateTime date) async {
    final user = SupabaseService.currentUser;
    if (user == null || !mounted) return;
    setState(() => _dayLoad = true);
    try {
      final start = DateTime(date.year, date.month, date.day);
      final end   = start.add(const Duration(days: 1));
      final rows  = await SupabaseService.getStepsHistory(
          userId: user.id, from: start, to: end);
      if (!mounted) return;
      setState(() {
        if (rows.isEmpty) {
          _daySteps = 0;
          _dayCal   = 0;
          _dayDistM = 0.0;
        } else {
          final row  = rows.first;
          _daySteps  = (row['steps'] as num? ?? 0).toInt();
          _dayCal    = (row['calories'] as num? ?? 0).toInt();
          _dayDistM  = (row['distance_m'] as num? ?? 0.0).toDouble();
        }
        // No 15-min interval breakdown available for past days
        _stepsSlots = List.filled(96, 0);
        _calSlots   = List.filled(96, 0);
        _distSlots  = List.filled(96, 0.0);
      });
    } catch (_) {}
    if (mounted) setState(() => _dayLoad = false);
  }

  // ── Date selection ────────────────────────────────────────────────────────

  void _onDateSelected(DateTime date) {
    final today        = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    final startOfDate  = DateTime(date.year, date.month, date.day);
    if (startOfDate.isAfter(startOfToday)) return; // block future dates

    setState(() => _selectedDate = date);

    if (_isToday(date)) {
      // Restore cached today totals immediately, then re-sync from ring
      setState(() {
        _daySteps = _totalSteps;
        _dayCal   = _totalCal;
        _dayDistM = _totalDistM;
      });
      _syncFromRing();
    } else {
      // Clear slots — past days have no interval data
      setState(() {
        _stepsSlots = List.filled(96, 0);
        _calSlots   = List.filled(96, 0);
        _distSlots  = List.filled(96, 0.0);
      });
      _loadPastDayData(date);
    }
  }

  // ── Display value getters ─────────────────────────────────────────────────

  int get _dispSteps => _daySteps;
  int get _dispCal   => _dayCal;
  double get _dispDistM => _dayDistM;

  String get _dayLabel {
    if (_isToday(_selectedDate)) return 'Today';
    return '${_selectedDate.day} ${_monthAbbr[_selectedDate.month - 1]}';
  }

  bool get _loading => _dayLoad;

  // ── Activity score ────────────────────────────────────────────────────────

  int get _activityScore {
    final avgSteps = _dispSteps.toDouble();
    final avgCal   = _dispCal.toDouble();
    final avgDistM = _dispDistM;
    final s = (avgSteps / 8000 * 60).clamp(0.0, 60.0);
    final c = (avgCal   / 250   * 25).clamp(0.0, 25.0);
    final d = (avgDistM / 5000  * 15).clamp(0.0, 15.0);
    return (s + c + d).round().clamp(0, 100);
  }

  String get _scoreLabel {
    final s = _activityScore;
    if (s == 0)  return 'Lack of exercise';
    if (s < 25)  return 'Sedentary';
    if (s < 50)  return 'Lightly active';
    if (s < 75)  return 'Moderately active';
    return 'Highly active';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        centerTitle: true,
        leading: Center(
          child: _circleIconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 16),
            onTap: () => Navigator.pop(context),
          ),
        ),
        title: Text('Activity', style: _t(17, w: FontWeight.w600)),
        actions: [
          Center(
            child: _circleIconButton(
              icon: const Icon(Icons.more_vert_rounded,
                  color: Colors.white, size: 18),
              onTap: () {},
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFFC9A86E),
        backgroundColor: const Color(0xFF1C1C1C),
        onRefresh: () async {
          if (_isToday(_selectedDate)) {
            await _syncFromRing();
          } else {
            await _loadPastDayData(_selectedDate);
          }
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Interactive date strip ───────────────────────────────────
              _DateStrip(
                now: now,
                selectedDate: _selectedDate,
                onDateSelected: _onDateSelected,
              ),
              Divider(
                color: Colors.white.withValues(alpha: 0.06),
                height: 0.5,
                thickness: 0.5,
              ),

              // ── Activity Score ───────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                child: _ActivityScore(
                    score: _activityScore,
                    label: _scoreLabel,
                    loading: _loading),
              ),

              // ── Workout and Sports link ──────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/workouts'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                    decoration: _glass(r: 16),
                    child: Row(children: [
                      Text('Workout and Sports',
                          style: _t(14, w: FontWeight.w500, c: Colors.white.withValues(alpha: 0.95))),
                      const Spacer(),
                      Icon(Icons.chevron_right_rounded,
                          color: Colors.white.withValues(alpha: 0.35),
                          size: 20),
                    ]),
                  ),
                ),
              ),

              // ── Stats row ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(children: [
                  Expanded(
                      child: _StatCard(
                          label: 'Total Steps',
                          value: _dispSteps > 0 ? '$_dispSteps' : '-- --',
                          color: _kStepsColor)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _StatCard(
                          label: 'Total Mileage',
                          value: _dispDistM > 0
                              ? '${(_dispDistM / 1000).toStringAsFixed(2)} km'
                              : '-- --',
                          color: _kDistColor)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _StatCard(
                          label: 'Total Calories', // Capitalized for UI consistency
                          value: _dispCal > 0 ? '$_dispCal' : '-- --',
                          color: _kCalColor)),
                ]),
              ),

              // ── Day charts ───────────────────────────────────────────────
              ...[
                _chartPad(_ChartCard(
                  title: 'STEPS',
                  subtitle: _dayLabel.toUpperCase(),
                  summary: _daySteps > 0 ? '$_daySteps steps' : '0 steps',
                  color: _kStepsColor,
                  values: _toHourlyInt(_stepsSlots),
                  xLabels: _hourXLabels,
                  loading: _loading,
                )),
                _chartPad(_ChartCard(
                  title: 'DISTANCE',
                  subtitle: _dayLabel.toUpperCase(),
                  summary: _dayDistM > 0
                      ? '${_dayDistM.toStringAsFixed(0)} m'
                      : '0 km',
                  color: _kDistColor,
                  values: _toHourlyDbl(_distSlots),
                  xLabels: _hourXLabels,
                  loading: _loading,
                )),
                _chartPad(_ChartCard(
                  title: 'CALORIES',
                  subtitle: _dayLabel.toUpperCase(),
                  summary: _dayCal > 0 ? '$_dayCal kcal' : '0 kcal',
                  color: _kCalColor,
                  values: _toHourlyInt(_calSlots),
                  xLabels: _hourXLabels,
                  loading: _loading,
                )),
              ],

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chartPad(Widget child) =>
      Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: child);

List<double> _toHourlyInt(List<int> slots) => List.generate(
      24,
      (h) => slots
          .sublist(h * 4, h * 4 + 4)
          .fold(0, (a, b) => a + b)
          .toDouble());

  List<double> _toHourlyDbl(List<double> slots) => List.generate(
      24,
      (h) =>
          slots.sublist(h * 4, h * 4 + 4).fold(0.0, (a, b) => a + b));

  static const _hourXLabels = ['12am', '6am', '12pm', '6pm', '12am'];
}

// ── Date strip ────────────────────────────────────────────────────────────────

class _DateStrip extends StatelessWidget {
  final DateTime now;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;

  const _DateStrip({
    required this.now,
    required this.selectedDate,
    required this.onDateSelected,
  });

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final startOfToday = DateTime(now.year, now.month, now.day);

    return SizedBox(
      height: 54,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: 10,
        itemBuilder: (_, i) {
          final offset     = i - 6; // -6 … +3
          final date       = now.add(Duration(days: offset));
          final startOfDay = DateTime(date.year, date.month, date.day);
          final isToday    = _sameDay(date, now);
          final isSelected = _sameDay(date, selectedDate);
          final isFuture   = startOfDay.isAfter(startOfToday);

          return GestureDetector(
            onTap: isFuture ? null : () => onDateSelected(date),
            child: Center(
              child: isSelected
                  ? Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        isToday
                            ? 'Today, ${date.day} ${_monthAbbr[date.month - 1]}'
                            : '${date.day} ${_monthAbbr[date.month - 1]}',
                        style: _t(13,
                            w: FontWeight.w500,
                            c: Colors.white.withValues(alpha: 0.95)),
                      ),
                    )
                  : Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      child: Text(
                        '${date.day}',
                        style: _t(14,
                            w: FontWeight.w400,
                            c: isFuture
                                ? Colors.white.withValues(alpha: 0.18)
                                : Colors.white.withValues(alpha: 0.4)),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}

// ── Activity score ────────────────────────────────────────────────────────────

class _ActivityScore extends StatelessWidget {
  final int score;
  final String label;
  final bool loading;
  const _ActivityScore(
      {required this.score, required this.label, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ACTIVITY SCORE',
            style: _t(10,
                w: FontWeight.w700,
                c: const Color(0xFFC9A86E),
                ls: 1.6)),
        const SizedBox(height: 8),
        loading
            ? const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                    color: Color(0xFFC9A86E), strokeWidth: 2))
            : Text('$score',
                style: _t(54,
                    w: FontWeight.w300,
                    c: Colors.white.withValues(alpha: 0.95))),
        const SizedBox(height: 4),
        Text(label,
            style: _t(14, c: Colors.white.withValues(alpha: 0.55))),
      ],
    );
  }
}

// ── Stat card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatCard(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: _glass(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: _t(10,
                  w: FontWeight.w500,
                  c: Colors.white.withValues(alpha: 0.4))),
          const SizedBox(height: 12),
          Text(value,
              style: _t(18,
                  w: FontWeight.w600,
                  c: Colors.white.withValues(alpha: 0.95)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('know more',
                  style: _t(9,
                      w: FontWeight.w400,
                      c: Colors.white.withValues(alpha: 0.35))),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.35), size: 10),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Chart card ────────────────────────────────────────────────────────────────

class _ChartCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final String summary;
  final Color color;
  final List<double> values;
  final List<String> xLabels;
  final bool loading;

  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.summary,
    required this.color,
    required this.values,
    required this.xLabels,
    required this.loading,
  });

  @override
  State<_ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<_ChartCard> {
  int? _selectedIndex;

  List<double> get _norm {
    if (widget.values.isEmpty) return [];
    final mx = widget.values.reduce((a, b) => a > b ? a : b);
    if (mx <= 0) return List.filled(widget.values.length, 0.0);
    return widget.values.map((v) => v / mx).toList();
  }

  void _handleTapOrDrag(Offset localPos, Size size) {
    if (widget.values.isEmpty) return;
    final n = widget.values.length;
    final slotW = size.width / n;
    int idx = (localPos.dx / slotW).floor();
    idx = idx.clamp(0, n - 1);
    if (_selectedIndex != idx) {
      setState(() {
        _selectedIndex = idx;
      });
    }
  }

  void _clearSelection() {
    if (_selectedIndex != null) {
      setState(() {
        _selectedIndex = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final norm    = _norm;
    final hasData = norm.isNotEmpty && norm.any((v) => v > 0);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: _glass(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.title.toUpperCase(),
                style: _t(11,
                    w: FontWeight.w700,
                    c: Colors.white.withValues(alpha: 0.9),
                    ls: 0.8),
              ),
              Text(
                widget.summary.toUpperCase(),
                style: _t(11,
                    w: FontWeight.w700,
                    c: Colors.white.withValues(alpha: 0.9),
                    ls: 0.8),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Chart body
          SizedBox(
            height: 239,
            width: double.infinity,
            child: widget.loading
                ? Center(
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: widget.color, strokeWidth: 1.5)))
                : !hasData
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bar_chart_rounded,
                                color: Colors.white.withValues(alpha: 0.13),
                                size: 28),
                            const SizedBox(height: 6),
                            Text('No data',
                                style: _t(11,
                                    c: Colors.white.withValues(alpha: 0.3))),
                          ],
                        ))
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final size = Size(constraints.maxWidth, constraints.maxHeight);
                          return GestureDetector(
                            // Added LongPress explicitly for "click and hold" behavior
                            onLongPressStart: (details) => _handleTapOrDrag(details.localPosition, size),
                            onLongPressMoveUpdate: (details) => _handleTapOrDrag(details.localPosition, size),
                            onLongPressEnd: (_) => _clearSelection(),
                            onTapDown: (details) => _handleTapOrDrag(details.localPosition, size),
                            onTapUp: (_) => _clearSelection(),
                            onTapCancel: () => _clearSelection(),
                            // Using HorizontalDrag instead of Pan to allow vertical scrolling safely
                            onHorizontalDragStart: (details) => _handleTapOrDrag(details.localPosition, size),
                            onHorizontalDragUpdate: (details) => _handleTapOrDrag(details.localPosition, size),
                            onHorizontalDragEnd: (_) => _clearSelection(),
                            onHorizontalDragCancel: () => _clearSelection(),
                            child: CustomPaint(
                              size: size,
                              painter: _BarPainter(
                                values: norm,
                                rawValues: widget.values,
                                color: widget.color,
                                selectedIndex: _selectedIndex,
                              ),
                            ),
                          );
                        },
                      ),
          ),

          // X-axis labels
          if (!widget.loading) ...[
            const SizedBox(height: 8),
            _XAxisRow(labels: widget.xLabels, count: widget.values.length),
          ],
        ],
      ),
    );
  }
}

// ── X-axis row ────────────────────────────────────────────────────────────────

class _XAxisRow extends StatelessWidget {
  final List<String> labels;
  final int count;
  const _XAxisRow({required this.labels, required this.count});

  @override
  Widget build(BuildContext context) {
    final toShow = labels.length <= 10 ? labels : _sparse(labels);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: toShow
          .map((l) => Text(l,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 9)))
          .toList(),
    );
  }

  List<String> _sparse(List<String> all) {
    final step = (all.length / 6).ceil();
    final out  = <String>[];
    for (int i = 0; i < all.length; i += step) {
      out.add(all[i]);
    }
    if (out.last != all.last) out.add(all.last);
    return out;
  }
}

// ── Bar chart painter ─────────────────────────────────────────────────────────

class _BarPainter extends CustomPainter {
  final List<double> values;
  final List<double> rawValues;
  final Color color;
  final int? selectedIndex;

  const _BarPainter({
    required this.values,
    required this.rawValues,
    required this.color,
    required this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final n     = values.length;
    final slotW = size.width / n;
    final barW  = n > 20
        ? (slotW * 0.6).clamp(1.5, 6.0)
        : (slotW * 0.6).clamp(6.0, 24.0);
    final padL  = (slotW - barW) / 2;

    // Draw horizontal dashed grid lines (at 25%, 50%, 75% height)
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    for (int j = 1; j <= 3; j++) {
      final y = size.height * (j * 0.25);
      _drawDashedLine(canvas, Offset(0, y), Offset(size.width, y), gridPaint, 4.0, 3.0);
    }

    // Draw bars
    for (int i = 0; i < n; i++) {
      if (values[i] <= 0) continue;
      final ratio = values[i];
      final barH  = (ratio * size.height * 0.75).clamp(2.0, size.height * 0.75);
      final x     = i * slotW + padL;
      final yTop  = size.height - barH;

      // Select color based on ratio (as seen in Graphs-Activity.png)
      Color barColor;
      if (ratio >= 0.9) {
        barColor = const Color(0xFFC9A86E);
      } else if (ratio >= 0.65) {
        barColor = Colors.white.withValues(alpha: 0.85);
      } else {
        barColor = const Color(0xFF6BC99B);
      }

      if (selectedIndex == i) {
        barColor = barColor.withValues(alpha: 1.0);
      }

      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(x, yTop, x + barW, size.height),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        ),
        Paint()..color = barColor,
      );
    }

    // Draw tooltip
    if (selectedIndex != null &&
        selectedIndex! >= 0 &&
        selectedIndex! < values.length &&
        values[selectedIndex!] > 0) {
      final idx = selectedIndex!;
      final ratio = values[idx];
      final rawVal = rawValues[idx];
      final barH  = (ratio * size.height * 0.75).clamp(2.0, size.height * 0.75);
      final xCenter = idx * slotW + padL + barW / 2;
      final yTop  = size.height - barH;

      final valStr = _formatValue(rawVal);

      final textPainter = TextPainter(
        text: TextSpan(
          text: valStr,
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      const padX = 8.0;
      const padY = 4.0;
      final tooltipW = textPainter.width + padX * 2;
      final tooltipH = textPainter.height + padY * 2;

      double rectLeft = xCenter - tooltipW / 2;
      rectLeft = rectLeft.clamp(2.0, size.width - tooltipW - 2.0);
      
      double rectTop = yTop - tooltipH - 6.0;
      bool isBelow = false;

      // Ensure tooltip remains visible if space above is insufficient
      if (rectTop < 0) {
        rectTop = yTop + 6.0;
        isBelow = true;
      }

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(rectLeft, rectTop, tooltipW, tooltipH),
          const Radius.circular(6),
        ),
        Paint()..color = const Color(0xFF000000),
      );

      final path = Path();
      if (isBelow) {
        path.moveTo(xCenter - 4, rectTop);
        path.lineTo(xCenter + 4, rectTop);
        path.lineTo(xCenter, yTop + 2);
      } else {
        path.moveTo(xCenter - 4, rectTop + tooltipH);
        path.lineTo(xCenter + 4, rectTop + tooltipH);
        path.lineTo(xCenter, yTop - 2);
      }
      path.close();
      
      canvas.drawPath(path, Paint()..color = const Color(0xFF000000));

      textPainter.paint(
        canvas,
        Offset(rectLeft + padX, rectTop + padY),
      );
    }
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint, double dashWidth, double dashSpace) {
    double distance = (p2 - p1).distance;
    int count = (distance / (dashWidth + dashSpace)).floor();
    for (int i = 0; i < count; i++) {
      double startFraction = (i * (dashWidth + dashSpace)) / distance;
      double endFraction = (startFraction + dashWidth / distance).clamp(0.0, 1.0);
      canvas.drawLine(
        Offset.lerp(p1, p2, startFraction)!,
        Offset.lerp(p1, p2, endFraction)!,
        paint,
      );
    }
  }

  String _formatValue(double val) {
    if (val == val.toInt().toDouble()) {
      return val.toInt().toString();
    }
    return val.toStringAsFixed(1);
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.values != values ||
      old.rawValues != rawValues ||
      old.color != color ||
      old.selectedIndex != selectedIndex;
}