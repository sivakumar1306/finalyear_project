import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/supabase_service.dart';

class LogPeriodScreen extends StatefulWidget {
  final DateTime initialDate;
  final Set<DateTime> periodDays;
  final Set<DateTime> fertileDays;
  final Future<void> Function(
    DateTime date,
    String flow,
    String color,
    String notes,
    Set<String> feelings,
    Set<String> pains,
    bool pms,
  ) onSave;

  const LogPeriodScreen({
    super.key,
    required this.initialDate,
    required this.periodDays,
    required this.fertileDays,
    required this.onSave,
  });

  @override
  State<LogPeriodScreen> createState() => _LogPeriodScreenState();
}

class _LogPeriodScreenState extends State<LogPeriodScreen> {
  late DateTime _calendarMonth;
  DateTime? _selectedDate;
  String _flow = 'Light';
  String _color = 'Red';
  String _notes = '';
  final Set<String> _feelings = {};
  final Set<String> _pains = {};
  bool _pms = false;
  bool _saving = false;
  bool _loading = false;
  late TextEditingController _notesCtrl;

  static const _kMonthsShort = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _calendarMonth = DateTime(widget.initialDate.year, widget.initialDate.month, 1);
    _notesCtrl = TextEditingController(text: _notes);
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  DateTime _d(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  TextStyle _inter(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = Colors.white,
  }) {
    return TextStyle(
      fontFamily: 'Inter',
      fontSize: size,
      fontWeight: weight,
      color: color,
    );
  }

  Future<void> _loadDataForSelectedDate(DateTime date) async {
    setState(() {
      _selectedDate = date;
      _loading = true;
    });

    try {
      final user = SupabaseService.currentUser;
      if (user != null) {
        final symptom = await SupabaseService.getSymptomsForDate(user.id, date);
        if (symptom != null) {
          _flow = symptom['flow_intensity'] as String? ?? 'Light';
          _color = symptom['flow_color'] as String? ?? 'Red';
          
          final moodStr = symptom['mood'] as String? ?? '';
          _feelings.clear();
          if (moodStr.isNotEmpty) {
            _feelings.addAll(moodStr.split(', ').where((e) => e.isNotEmpty));
          }
          
          _pains.clear();
          if (symptom['cramps'] == true) _pains.add('Cramps');
          
          String rawNotes = symptom['notes'] as String? ?? '';
          
          _pms = false;
          if (rawNotes.contains('PMS: Yes')) {
            _pms = true;
            rawNotes = rawNotes.replaceAll('PMS: Yes', '').trim();
          }
          
          final painRegex = RegExp(r'Pain:\s*(.*?)(?:\n|$)');
          final painMatch = painRegex.firstMatch(rawNotes);
          if (painMatch != null) {
            final pStr = painMatch.group(1) ?? '';
            _pains.addAll(pStr.split(', ').where((e) => e.isNotEmpty));
            rawNotes = rawNotes.replaceFirst(painRegex, '').trim();
          }
          
          if (_pains.isEmpty) {
            _pains.add('Pain Free');
          }
          
          _notes = rawNotes;
          _notesCtrl.text = _notes;
        } else {
          _flow = 'Light';
          _color = 'Red';
          _notes = '';
          _notesCtrl.text = _notes;
          _feelings.clear();
          _pains.clear();
          _pains.add('Pain Free');
          _pms = false;
        }
      }
    } catch (e) {
      // Ignore errors for now
      debugPrint('Error loading symptoms: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Log a Period', style: _inter(16, weight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMonthHeader(),
              const SizedBox(height: 16),
              _buildCalendarGrid(),
              if (_selectedDate != null) ...[
                const SizedBox(height: 32),
                if (_loading)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: CircularProgressIndicator(color: AppTheme.gold),
                  ))
                else
                  _buildOptionsView(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
          onPressed: () {
            setState(() {
              _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month - 1, 1);
            });
          },
        ),
        Text(
          '${_kMonthsShort[_calendarMonth.month - 1]} ${_calendarMonth.year}',
          style: _inter(16, weight: FontWeight.w600, color: Colors.white),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded, color: Colors.white),
          onPressed: () {
            setState(() {
              _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 1);
            });
          },
        ),
      ],
    );
  }

  Widget _buildCalendarGrid() {
    final firstOfMonth = DateTime(_calendarMonth.year, _calendarMonth.month, 1);
    final daysInMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 0).day;
    final startOffset = firstOfMonth.weekday % 7; 
    
    final totalCells = startOffset + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return Column(
      children: List.generate(rows, (rowIndex) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (colIndex) {
              final cellIndex = rowIndex * 7 + colIndex;
              final dayNum = cellIndex - startOffset + 1;
              final isCurrentMonth = dayNum > 0 && dayNum <= daysInMonth;
              
              if (!isCurrentMonth) {
                return const SizedBox(width: 44, height: 48);
              }

              final cellDate = DateTime(_calendarMonth.year, _calendarMonth.month, dayNum);
              final d = _d(cellDate);
              final isPeriod = widget.periodDays.contains(d);
              final isFertile = widget.fertileDays.contains(d);
              final isSelected = _selectedDate != null && _d(_selectedDate!) == d;

              return GestureDetector(
                onTap: () {
                  _loadDataForSelectedDate(cellDate);
                },
                child: Container(
                  width: 44,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(10),
                    border: isSelected ? Border.all(color: AppTheme.gold, width: 1.5) : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$dayNum',
                        style: _inter(
                          14, 
                          color: isSelected ? AppTheme.gold : Colors.white,
                          weight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      if (isPeriod || isFertile) const SizedBox(height: 2),
                      if (isPeriod)
                        const Icon(Icons.water_drop_rounded, color: AppTheme.danger, size: 10)
                      else if (isFertile)
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Colors.cyan,
                            shape: BoxShape.circle,
                          ),
                        )
                      else
                        const SizedBox(height: 10),
                    ],
                  ),
                ),
              );
            }),
          ),
        );
      }),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: _inter(12, weight: FontWeight.w600, color: AppTheme.textSec).copyWith(letterSpacing: 1.5),
      ),
    );
  }

  Widget _buildMultiSelectRow(List<String> options, Set<String> selected, void Function(String) onToggle) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((opt) {
          final sel = selected.contains(opt);
          return GestureDetector(
            onTap: () => onToggle(opt),
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: sel ? AppTheme.gold : const Color(0xFF111111),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: sel ? AppTheme.gold : Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              child: Text(
                opt,
                style: _inter(
                  14,
                  color: sel ? Colors.black : Colors.white,
                  weight: sel ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSingleSelectRow(List<String> options, bool Function(String) isSelected, void Function(String) onSelect) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((opt) {
          final sel = isSelected(opt);
          return GestureDetector(
            onTap: () => onSelect(opt),
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: sel ? AppTheme.gold : const Color(0xFF111111),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: sel ? AppTheme.gold : Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              child: Text(
                opt,
                style: _inter(
                  14,
                  color: sel ? Colors.black : Colors.white,
                  weight: sel ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOptionsView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: ['Light', 'Medium', 'Heavy'].map((f) {
              final sel = _flow == f;
              return GestureDetector(
                onTap: () => setState(() => _flow = f),
                child: Container(
                  width: 90,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: sel ? AppTheme.gold : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    f,
                    style: _inter(
                      13,
                      color: sel ? Colors.black : Colors.white.withValues(alpha: 0.6),
                      weight: sel ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: ['Red', 'Brown'].map((c) {
              final sel = _color == c;
              return GestureDetector(
                onTap: () => setState(() => _color = c),
                child: Container(
                  width: 90,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: sel ? AppTheme.gold : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    c,
                    style: _inter(
                      13,
                      color: sel ? Colors.black : Colors.white.withValues(alpha: 0.6),
                      weight: sel ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 24),
        
        _buildSectionTitle('FEELING'),
        _buildMultiSelectRow(
          ['Mood swings', 'Not in control', 'Random Cravings'],
          _feelings,
          (opt) => setState(() {
            if (_feelings.contains(opt)) {
              _feelings.remove(opt);
            } else {
              _feelings.add(opt);
            }
          }),
        ),
        const SizedBox(height: 24),

        _buildSectionTitle('PAIN'),
        _buildMultiSelectRow(
          ['Pain Free', 'Cramps', 'Ovulation', 'Tender Breasts'],
          _pains,
          (opt) => setState(() {
            if (opt == 'Pain Free') {
              _pains.clear();
              _pains.add(opt);
            } else {
              _pains.remove('Pain Free');
              if (_pains.contains(opt)) {
                _pains.remove(opt);
              } else {
                _pains.add(opt);
              }
            }
          }),
        ),
        const SizedBox(height: 24),

        _buildSectionTitle('PMS'),
        _buildSingleSelectRow(
          ['PMS'],
          (opt) => _pms,
          (opt) => setState(() => _pms = !_pms),
        ),
        const SizedBox(height: 24),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _notesCtrl,
                  onChanged: (v) => _notes = v,
                  style: _inter(14, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Any notes you would like to add,\nmedications you take etc',
                    hintStyle: _inter(13, color: AppTheme.textSec),
                    border: InputBorder.none,
                  ),
                  maxLines: 2,
                  minLines: 1,
                ),
              ),
              const Icon(Icons.mic, color: AppTheme.gold, size: 20),
            ],
          ),
        ),
        const SizedBox(height: 40),
        
        GestureDetector(
          onTap: _saving ? null : () async {
            setState(() => _saving = true);
            await widget.onSave(_selectedDate!, _flow, _color, _notes, _feelings, _pains, _pms);
            setState(() => _saving = false);
            if (mounted) Navigator.pop(context);
          },
          child: Container(
            width: double.infinity,
            height: 50,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.danger, Color(0xFF991B1B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text(
                      'Save',
                      style: _inter(15, weight: FontWeight.w700, color: Colors.white),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}
