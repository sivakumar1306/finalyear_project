import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../theme/app_theme.dart';

// Client-specified accent for this screen's design — matches DESIGN.md's
// primary accent (#C9A86E), distinct from AppTheme.gold used elsewhere.
const Color _kGold = Color(0xFFC9A86E);

class _ChatMessage {
  final String text;
  final bool fromUser;
  _ChatMessage(this.text, this.fromUser);
}

class AssistScreen extends StatefulWidget {
  const AssistScreen({super.key});

  @override
  State<AssistScreen> createState() => _AssistScreenState();
}

class _AssistScreenState extends State<AssistScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [
    _ChatMessage(
      "Hi, I'm your AI health coach. Ask me about your heart rate, "
      "stress, sleep, blood pressure, SpO2, or activity today.",
      false,
    ),
  ];

  bool _seeding = false;
  bool _isTyping = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _seedDemoData() async {
    if (_seeding) return;
    setState(() => _seeding = true);
    try {
      await context.read<BleProvider>().seedDemoData(hoursBack: 3);
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(
          "Loaded 3 hours of demo vitals — ask me anything.",
          false,
        ));
      });
      _scrollToBottom();
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final ble = context.read<BleProvider>();
    final reply = _generateReply(text, ble);
    setState(() {
      _messages.add(_ChatMessage(text, true));
      _isTyping = true;
    });
    _controller.clear();
    _scrollToBottom();
    // Purely presentational delay so the "AI ASSIST" typing indicator has a
    // moment on screen — the reply content/logic above is unchanged.
    Future.delayed(const Duration(milliseconds: 550), () {
      if (!mounted) return;
      setState(() {
        _isTyping = false;
        _messages.add(_ChatMessage(reply, false));
      });
      _scrollToBottom();
    });
  }

  String _generateReply(String input, BleProvider ble) {
    final q = input.toLowerCase();

    if (q.contains('heart') || q.contains('hr') || q.contains('bpm')) {
      return 'Your heart rate today: avg ${ble.todayAvgHr} bpm, '
          'range ${ble.todayMinHr}-${ble.todayMaxHr} bpm. '
          '${ble.todayAvgHr > 0 ? "That's within a normal resting range." : "No readings yet today — try a measurement."}';
    }
    if (q.contains('stress')) {
      return 'Your stress level right now is ${ble.latestStressValue}, '
          'with a daily average of ${ble.todayAvgStress} '
          '(range ${ble.todayMinStress}-${ble.todayMaxStress}). '
          '${ble.todayAvgStress > 60 ? "Consider a short breathing break." : "You're holding up well today."}';
    }
    if (q.contains('sleep')) {
      final hours = ble.todaySleepDuration / 60;
      return 'Last night you slept ${hours.toStringAsFixed(1)} hours '
          'with a sleep score of ${ble.todaySleepScore}.';
    }
    if (q.contains('pressure') || q.contains('bp')) {
      return 'Your latest blood pressure reading is '
          '${ble.latestBpSbp}/${ble.latestBpDbp} mmHg.';
    }
    if (q.contains('oxygen') || q.contains('spo2') || q.contains('o2')) {
      return 'Your blood oxygen today: avg ${ble.todayAvgSpo2}%, '
          'range ${ble.todayMinSpo2}-${ble.todayMaxSpo2}%.';
    }
    if (q.contains('hrv')) {
      return 'Your average HRV today is ${ble.todayAvgHrv} ms.';
    }
    if (q.contains('temp')) {
      return 'Your latest skin temperature reading is '
          '${ble.latestTempC.toStringAsFixed(1)}°C.';
    }
    if (q.contains('step') || q.contains('activity') || q.contains('walk')) {
      return "You've taken ${ble.todaySteps} steps today, burning "
          '${ble.todayCalories} kcal over ${ble.todayDistanceM.toStringAsFixed(0)} m.';
    }
    if (q.contains('hello') || q.contains('hi') || q.contains('hey')) {
      return "Hello! I'm keeping an eye on your vitals. What would you like to check?";
    }
    if (q.contains('thank')) {
      return "You're welcome. Stay healthy!";
    }
    return "I can tell you about your heart rate, stress, sleep, blood "
        "pressure, SpO2, HRV, temperature, or activity — just ask.";
  }

  // Highlights key numbers/units/status-words in gold within an assistant
  // reply — presentation only, does not touch the reply text itself.
  static final RegExp _highlightPattern = RegExp(
    r'(\d+(\.\d+)?\s*-\s*\d+(\.\d+)?\s*(bpm|mmHg|%|ms|kcal|m|°C))'
    r'|(\d+(\.\d+)?\s*(bpm|mmHg|%|ms|kcal|m|°C|steps|min|minutes|hours))'
    r'|\b(high|low|elevated|normal|steady)\b',
    caseSensitive: false,
  );

  List<InlineSpan> _highlightedSpans(String text) {
    const baseStyle = TextStyle(
      color: Colors.white,
      fontSize: 14,
      height: 1.45,
    );
    const goldStyle = TextStyle(
      color: _kGold,
      fontSize: 14,
      height: 1.45,
      fontWeight: FontWeight.w600,
    );
    final spans = <InlineSpan>[];
    var last = 0;
    for (final match in _highlightPattern.allMatches(text)) {
      if (match.start > last) {
        spans.add(TextSpan(text: text.substring(last, match.start), style: baseStyle));
      }
      spans.add(TextSpan(text: match.group(0), style: goldStyle));
      last = match.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: baseStyle));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'AI assist',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _seeding ? null : _seedDemoData,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: _seeding
                        ? const Padding(
                            padding: EdgeInsets.all(9),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _kGold,
                            ),
                          )
                        : const Icon(
                            Icons.dataset_outlined,
                            color: _kGold,
                            size: 18,
                          ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return const _TypingIndicator();
                }
                final m = _messages[index];
                if (m.fromUser) {
                  return Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.78,
                      ),
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: _kGold.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _kGold.withValues(alpha: 0.25), width: 0.5),
                      ),
                      child: Text(
                        m.text,
                        style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.45),
                      ),
                    ),
                  );
                }
                return Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.9,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 6),
                          child: Text(
                            'AI ASSIST',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.35),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: AppTheme.card,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text.rich(TextSpan(children: _highlightedSpans(m.text))),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppTheme.div),
              ),
              padding: const EdgeInsets.only(left: 20, right: 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onSubmitted: (_) => _send(),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Ask about your health ...',
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _send,
                    icon: const Icon(Icons.mic_none_rounded, color: _kGold, size: 22),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              'AI ASSIST',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(20),
            ),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    final t = (_controller.value - i * 0.2) % 1.0;
                    final opacity = 0.3 + 0.7 * (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _kGold.withValues(alpha: opacity),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
