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
        barrierColor: Colors.transparent,
        barrierDismissible: true,
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

  late AnimationController _cursorController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _waveController;

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
    if (_disposed || !mounted) return;
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
    if (_disposed || !mounted) return;
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

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Dismissible background overlay with backdrop blur
          Positioned.fill(
            child: GestureDetector(
              onTap: _cancel,
              behavior: HitTestBehavior.opaque,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.65),
                ),
              ),
            ),
          ),

          // Floating Glass Modal Sheet (Fully responsive, no clipping)
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Material(
                  color: Colors.transparent,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 380),
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                        decoration: BoxDecoration(
                          color: const Color(0xEC12100D),
                          border: Border.all(
                            color: AppTheme.goldTint,
                            width: 0.8,
                          ),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Top Header Row with Close X Button
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const SizedBox(width: 32),
                                  Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: AppTheme.gold,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      RichText(
                                        text: const TextSpan(
                                          style: TextStyle(
                                                                                        fontSize: 17,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          children: [
                                            TextSpan(
                                              text: "I'm ",
                                              style: TextStyle(
                                                  color: AppTheme.white92),
                                            ),
                                            TextSpan(
                                              text: "listening...",
                                              style: TextStyle(
                                                  color: AppTheme.gold),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  GestureDetector(
                                    onTap: _cancel,
                                    child: Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: AppTheme.white10,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: AppTheme.white15,
                                          width: 0.5,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.close_rounded,
                                        size: 16,
                                        color: AppTheme.white85,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 18),

                              // Mic Circle Animation
                              _MicCircle(pulseAnimation: _pulseAnimation),

                              const SizedBox(height: 16),

                              // Live Transcript Glass Container
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 44,
                                  maxWidth: 310,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0x0EFFFFFF),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: AppTheme.glassButtonBorder,
                                      width: 0.5,
                                    ),
                                  ),
                                  child: hasTranscript
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Flexible(
                                              child: Text(
                                                '"$transcriptText"',
                                                textAlign: TextAlign.center,
                                                maxLines: 3,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                                                                    fontSize: 13.5,
                                                  fontWeight: FontWeight.w400,
                                                  height: 1.4,
                                                  color: Color(0xEEFFFFFF),
                                                ),
                                              ),
                                            ),
                                            FadeTransition(
                                              opacity: _cursorController,
                                              child: Container(
                                                margin: const EdgeInsets.only(
                                                    left: 3),
                                                width: 2,
                                                height: 14,
                                                color: AppTheme.gold,
                                              ),
                                            ),
                                          ],
                                        )
                                      : const Center(
                                          child: Text(
                                            'Speak now... listening for your voice',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                                                            fontSize: 13,
                                              fontWeight: FontWeight.w400,
                                              fontStyle: FontStyle.italic,
                                              color: AppTheme.white50,
                                            ),
                                          ),
                                        ),
                                ),
                              ),

                              const SizedBox(height: 18),

                              // Animated Waveform
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
                                        for (int i = 0;
                                            i < _kWaveformBars.length;
                                            i++) ...[
                                          if (i > 0) const SizedBox(width: 4),
                                          _buildWaveBar(i),
                                        ],
                                      ],
                                    );
                                  },
                                ),
                              ),

                              const SizedBox(height: 20),

                              // Action Buttons: Cancel & Done
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  GestureDetector(
                                    onTap: _cancel,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 20, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: AppTheme.white10,
                                        border: Border.all(
                                          color: AppTheme.white15,
                                          width: 0.5,
                                        ),
                                        borderRadius: BorderRadius.circular(100),
                                      ),
                                      child: const Text(
                                        'Cancel',
                                        style: TextStyle(
                                                                                    fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: AppTheme.white85,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  GestureDetector(
                                    onTap: _stopAndReturn,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 22, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: AppTheme.gold,
                                        borderRadius:
                                            BorderRadius.circular(100),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppTheme.gold
                                                .withValues(alpha: 0.4),
                                            blurRadius: 16,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 10,
                                            height: 10,
                                            decoration: BoxDecoration(
                                              color: AppTheme.bg,
                                              borderRadius:
                                                  BorderRadius.circular(2),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const Text(
                                            'Done',
                                            style: TextStyle(
                                                                                            fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.bg,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 12),

                              // Subtitle Caption
                              const Text(
                                'Tap Done when finished or stop speaking for 4s',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                                                    fontSize: 11,
                                  fontWeight: FontWeight.w400,
                                  color: Color(0x70FFFFFF),
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
        ],
      ),
    );
  }

  Widget _buildWaveBar(int i) {
    final base = _kWaveformBars[i];
    final phase = i * (2 * pi / _kWaveformBars.length);
    final t = (sin(_waveController.value * 2 * pi + phase) + 1) / 2;
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
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x38C9A86E), width: 0.5),
              ),
            ),
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x52C9A86E), width: 0.5),
              ),
            ),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  center: Alignment.center,
                  radius: 0.5,
                  colors: [
                    AppTheme.goldMuted,
                    AppTheme.gold,
                    AppTheme.goldDusk,
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
                boxShadow: const [
                  BoxShadow(color: AppTheme.goldTint, blurRadius: 60),
                  BoxShadow(color: Color(0x66C9A86E), blurRadius: 30),
                ],
              ),
            ),
            const Icon(Icons.mic_rounded, size: 28, color: AppTheme.bgDim),
          ],
        ),
      ),
    );
  }
}
