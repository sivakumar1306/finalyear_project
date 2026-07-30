import 'dart:async';
import 'dart:math';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import '../../theme/app_theme.dart';

class VoiceListeningSheet extends StatefulWidget {
  const VoiceListeningSheet({super.key});

  /// Shows the voice listening overlay and returns the final transcript,
  /// or `null` if cancelled / error / empty.
  static Future<String?> show(BuildContext context) {
    return Navigator.of(context).push<String?>(
      PageRouteBuilder<String?>(
        opaque: false,
        barrierColor: Colors.black.withValues(
          alpha: 0.70,
        ), // Slightly reduced to let blur shine
        barrierDismissible: false,
        pageBuilder: (context, animation, secondaryAnimation) =>
            const VoiceListeningSheet(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );
  }

  @override
  State<VoiceListeningSheet> createState() => _VoiceListeningSheetState();
}

// Waveform bar spec — base height (px) and color alpha over the gold accent,
// matching the Figma frame. Animated around these base values (see
// _waveController) rather than fully random, so the shape still reads as
// the spec's silhouette while remaining visibly "alive".
const List<({double height, double alpha})> _kWaveformBars = [
  (height: 8, alpha: 0.5),
  (height: 14, alpha: 0.7),
  (height: 22, alpha: 0.95),
  (height: 16, alpha: 0.8),
  (height: 10, alpha: 0.55),
  (height: 18, alpha: 0.85),
  (height: 26, alpha: 1.0),
  (height: 20, alpha: 0.9),
  (height: 12, alpha: 0.6),
  (height: 8, alpha: 0.5),
  (height: 14, alpha: 0.7),
  (height: 6, alpha: 0.4),
];

class _VoiceListeningSheetState extends State<VoiceListeningSheet>
    with TickerProviderStateMixin {
  final SpeechToText _speech = SpeechToText();
  bool _disposed = false;

  String _partialTranscript = '';
  String _finalTranscript = '';
  bool _isListening = false;

  // Blinking text cursor at the end of the live transcript (matches the
  // "Line 19" caret element in the Figma spec).
  late AnimationController _cursorController;

  // Mic pulse — restored from the original design. Scoped to animate only
  // inside the mic's own fixed 110x110 box (see _MicCircle), so the pulse
  // never changes that box's layout size and can't shift anything else in
  // the card — that mismatch (scaling a box used directly in the Column)
  // was the actual cause of the earlier spacing drift, not the pulse itself.
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Waveform — restored animation, oscillating each bar around its spec
  // base height rather than fully random heights.
  late AnimationController _waveController;

  // Explicit silence-timeout fallback — the speech_to_text plugin's own
  // pauseFor doesn't reliably fire onStatus('notListening') on every device,
  // which was leaving the sheet listening indefinitely. This timer resets
  // on every new result (partial or final) and force-stops after 4s of no
  // new speech, guaranteeing the "pause for 4 seconds" behavior regardless
  // of plugin/platform quirks.
  static const _silenceTimeout = Duration(seconds: 4);
  Timer? _silenceTimer;

  @override
  void initState() {
    super.initState();

    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();

    _initSpeech();
  }

  Future<void> _initSpeech() async {
    bool available = false;
    try {
      available = await _speech.initialize(
        onStatus: _onStatus,
        onError: _onListenError,
      );
    } catch (e) {
      debugPrint('VoiceListeningSheet._initSpeech: $e');
      available = false;
    }

    if (_disposed) return;
    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission is needed for voice input.'),
            backgroundColor: AppTheme.card2,
          ),
        );
        Navigator.of(context).pop(null);
      }
      return;
    }

    _startListening();
  }

  void _startListening() {
    _speech.listen(
      onResult: _onResult,
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        listenMode: ListenMode.confirmation,
        partialResults: true,
      ),
    );
    setState(() => _isListening = true);
    _resetSilenceTimer();
  }

  void _resetSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(_silenceTimeout, () {
      if (_isListening) _stopAndReturn();
    });
  }

  void _onResult(SpeechRecognitionResult result) {
    _resetSilenceTimer();
    setState(() {
      if (result.finalResult) {
        _finalTranscript = result.recognizedWords.trim();
      } else {
        _partialTranscript = result.recognizedWords;
      }
    });
  }

  void _onStatus(String status) {
    // Auto-stop when silence timeout triggers notListening
    if (status == 'notListening' && _isListening) {
      _stopAndReturn();
    }
  }

  void _popWithNull() {
    if (mounted) Navigator.of(context).pop(null);
  }

  void _onListenError(SpeechRecognitionError error) {
    _popWithNull();
  }

  void _stopAndReturn() {
    _silenceTimer?.cancel();
    _speech.stop();
    setState(() => _isListening = false);
    final result = _finalTranscript.isNotEmpty
        ? _finalTranscript
        : _partialTranscript.trim();
    Navigator.of(context).pop(result.isEmpty ? null : result);
  }

  void _cancel() {
    _silenceTimer?.cancel();
    _speech.stop();
    Navigator.of(context).pop(null);
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _disposed = true;
    _speech.stop();
    _cursorController.dispose();
    _pulseController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasTranscript =
        _partialTranscript.isNotEmpty || _finalTranscript.isNotEmpty;
    final transcriptText = _finalTranscript.isNotEmpty
        ? _finalTranscript
        : _partialTranscript;

    // Bottom sheet-style overlay — scaled proportionally to device height
    final screenHeight = MediaQuery.of(context).size.height;
    final panelHeight = screenHeight * (443 / 812);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: panelHeight,
            child: ClipRect(
              // The blur is applied to the entire bottom half to match the prompt
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  padding: const EdgeInsets.only(
                    bottom: 24,
                    left: 16,
                    right: 16,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0x33000000), // Subtle darkening over the blur
                  ),
                  child: SafeArea(
                    top: false,
                    child: Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                          child: Container(
                            width: 367,
                            // Adjusted inner padding to be perfect according to Figma reference
                            padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xC70F0D09,
                              ), // rgba(15,13,9,0.78)
                              border: Border.all(
                                color: const Color(
                                  0x1FFFFFFF,
                                ), // rgba(255,255,255,0.12)
                                width: 0.5,
                              ),
                              borderRadius: BorderRadius.circular(28),
                            ),
                            // Wrapped in SingleChildScrollView: the fixed
                            // panelHeight above constrains this card's max
                            // height, so if the padding/gaps below (or a
                            // longer transcript) ever add up to more than
                            // that available space, the content now scrolls
                            // instead of throwing a RenderFlex overflow.
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // ── Mic circle (3 concentric rings + gradient core + pulse) ──
                                  _MicCircle(pulseAnimation: _pulseAnimation),

                                  const SizedBox(height: 24),

                                  // ── "I'm listening" label ──
                                  RichText(
                                    text: const TextSpan(
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 19,
                                        fontWeight: FontWeight.w400,
                                        letterSpacing: -0.02 * 19,
                                        height: 1.3,
                                      ),
                                      children: [
                                        TextSpan(
                                          text: "I'm ",
                                          style: TextStyle(
                                            color: Color(0xEBFFFFFF),
                                          ),
                                        ),
                                        TextSpan(
                                          text: "listening",
                                          style: TextStyle(
                                            color: AppTheme.gold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(height: 20),

                                  // ── Live transcript + blinking caret ──
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      minHeight: 38,
                                      maxWidth: 281,
                                    ),
                                    child: hasTranscript
                                        ? Row(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  '"$transcriptText',
                                                  textAlign: TextAlign.center,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontFamily: 'Inter',
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w400,
                                                    height: 1.5,
                                                    letterSpacing: -0.005 * 13,
                                                    color: Color(0x94FFFFFF),
                                                  ),
                                                ),
                                              ),
                                              FadeTransition(
                                                opacity: _cursorController,
                                                child: Container(
                                                  margin: const EdgeInsets.only(
                                                    left: 2,
                                                  ),
                                                  width: 1,
                                                  height: 14,
                                                  color: AppTheme.gold,
                                                ),
                                              ),
                                            ],
                                          )
                                        : const Center(
                                            child: Text(
                                              'Say something...',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontFamily: 'Inter',
                                                fontSize: 13,
                                                fontWeight: FontWeight.w400,
                                                height: 1.5,
                                                letterSpacing: -0.005 * 13,
                                                fontStyle: FontStyle.italic,
                                                color: Color(0x94FFFFFF),
                                              ),
                                            ),
                                          ),
                                  ),

                                  const SizedBox(height: 24),

                                  // ── Animated waveform bars ──
                                  SizedBox(
                                    width: 295,
                                    height: 28,
                                    child: AnimatedBuilder(
                                      animation: _waveController,
                                      builder: (context, _) {
                                        return Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            for (
                                              int i = 0;
                                              i < _kWaveformBars.length;
                                              i++
                                            ) ...[
                                              if (i > 0)
                                                const SizedBox(width: 4),
                                              _buildWaveBar(i),
                                            ],
                                          ],
                                        );
                                      },
                                    ),
                                  ),

                                  const SizedBox(height: 32),

                                  // ── Bottom controls: Cancel pill + Stop circle ──
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: SizedBox(
                                      width: 295,
                                      height: 50,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          // Cancel pill
                                          GestureDetector(
                                            onTap: _cancel,
                                            child: Container(
                                              width: 86,
                                              height: 41,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                color: const Color(0x0FFFFFFF),
                                                border: Border.all(
                                                  color: const Color(
                                                    0x1FFFFFFF,
                                                  ),
                                                  width: 0.5,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(100),
                                              ),
                                              child: const Text(
                                                'Cancel',
                                                style: TextStyle(
                                                  fontFamily: 'Inter',
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w500,
                                                  height: 1.5,
                                                  letterSpacing: -0.005 * 12.5,
                                                  color: Color(0xD9FFFFFF),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          // Stop circle
                                          GestureDetector(
                                            onTap: _stopAndReturn,
                                            child: Container(
                                              width: 50,
                                              height: 50,
                                              decoration: BoxDecoration(
                                                color: AppTheme.gold,
                                                shape: BoxShape.circle,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: AppTheme.gold
                                                        .withValues(
                                                          alpha: 0.35,
                                                        ),
                                                    blurRadius: 20,
                                                    offset: const Offset(0, 4),
                                                  ),
                                                ],
                                              ),
                                              child: Center(
                                                child: Container(
                                                  width: 16,
                                                  height: 16,
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xD9050505,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
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

                                  const SizedBox(height: 24),

                                  // ── Caption ──
                                  const Padding(
                                    padding: EdgeInsets.only(top: 2),
                                    child: SizedBox(
                                      width: 281,
                                      child: Text(
                                        'Tap stop or pause for 2 seconds',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          height: 1.5,
                                          letterSpacing: -0.005 * 11,
                                          color: Color(0xA6FFFFFF),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaveBar(int i) {
    final base = _kWaveformBars[i];
    // Each bar oscillates independently (phase offset by index) around its
    // own spec height, staying within a modest range so the overall
    // silhouette still matches the design while feeling alive.
    final phase = i * (2 * pi / _kWaveformBars.length);
    final t = (sin(_waveController.value * 2 * pi + phase) + 1) / 2; // 0..1
    final height = base.height * (0.7 + 0.3 * t);
    return Container(
      width: 3,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.gold.withValues(alpha: base.alpha),
        borderRadius: BorderRadius.circular(100),
      ),
    );
  }
}

/// The 3-ring mic icon — outer 110px ring, mid 86px ring, inner 64px
/// gradient-filled core with glow, mic icon centered on top. The pulse
/// animation is applied only inside this fixed 110x110 box (via Transform,
/// which is paint-only and doesn't change layout size), so it can't shift
/// anything else in the card regardless of how far it scales.
class _MicCircle extends StatelessWidget {
  final Animation<double> pulseAnimation;
  const _MicCircle({required this.pulseAnimation});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      height: 110,
      child: AnimatedBuilder(
        animation: pulseAnimation,
        builder: (context, child) {
          return Transform.scale(scale: pulseAnimation.value, child: child);
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Ellipse 12 — outer ring
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x38C9A86E), width: 0.5),
              ),
            ),
            // Ellipse 13 — mid ring
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x52C9A86E), width: 0.5),
              ),
            ),
            // Ellipse 14 — gradient-filled core with glow
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  center: Alignment.center,
                  radius: 0.5,
                  colors: [
                    Color(0xFFE0BC85),
                    Color(0xFFC9A86E),
                    Color(0xFF8E7A55),
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
                boxShadow: [
                  BoxShadow(color: const Color(0x33C9A86E), blurRadius: 60),
                  BoxShadow(color: const Color(0x66C9A86E), blurRadius: 30),
                ],
              ),
            ),
            // Mic icon
            const Icon(Icons.mic_rounded, size: 28, color: Color(0xD9050505)),
          ],
        ),
      ),
    );
  }
}
