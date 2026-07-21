import 'dart:math';
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
        barrierColor: Colors.black.withValues(alpha: 0.87),
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

class _VoiceListeningSheetState extends State<VoiceListeningSheet>
    with TickerProviderStateMixin {
  final SpeechToText _speech = SpeechToText();

  String _partialTranscript = '';
  String _finalTranscript = '';
  bool _isListening = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();

    // Pulse animation for the mic button
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Waveform animation
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _initSpeech();
  }

  Future<void> _initSpeech() async {
    bool available = false;
    try {
      available = await _speech.initialize(
        onStatus: _onStatus,
        onError: (SpeechRecognitionError error) => _popWithNull(),
      );
    } catch (_) {
      available = false;
    }

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
  }

  void _onResult(SpeechRecognitionResult result) {
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

  void _stopAndReturn() {
    _speech.stop();
    setState(() => _isListening = false);
    final result = _finalTranscript.isNotEmpty
        ? _finalTranscript
        : _partialTranscript.trim();
    Navigator.of(context).pop(result.isEmpty ? null : result);
  }

  void _cancel() {
    _speech.stop();
    Navigator.of(context).pop(null);
  }

  @override
  void dispose() {
    _speech.stop();
    _pulseController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 3),

            // ── Pulsing mic button ──
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: child,
                );
              },
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.gold.withValues(alpha: 0.15),
                  border: Border.all(
                    color: AppTheme.gold.withValues(alpha: 0.4),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.mic_rounded,
                  color: AppTheme.gold,
                  size: 42,
                ),
              ),
            ),

            const SizedBox(height: 28),

            // ── "I'm listening" label ──
            RichText(
              text: const TextSpan(
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                children: [
                  TextSpan(
                    text: "I'm ",
                    style: TextStyle(color: Colors.white),
                  ),
                  TextSpan(
                    text: "listening",
                    style: TextStyle(color: AppTheme.gold),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Live transcript ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _partialTranscript.isNotEmpty || _finalTranscript.isNotEmpty
                    ? '"${_finalTranscript.isNotEmpty ? _finalTranscript : _partialTranscript}"'
                    : 'Say something...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _partialTranscript.isNotEmpty ||
                          _finalTranscript.isNotEmpty
                      ? Colors.white70
                      : AppTheme.textSec,
                  fontSize: 15,
                  fontStyle: _partialTranscript.isEmpty &&
                          _finalTranscript.isEmpty
                      ? FontStyle.italic
                      : FontStyle.normal,
                ),
              ),
            ),

            const SizedBox(height: 32),

            // ── Animated waveform bars ──
            SizedBox(
              height: 40,
              child: AnimatedBuilder(
                animation: _waveController,
                builder: (context, _) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(9, (i) {
                      final phase = i * (2 * pi / 9);
                      final value =
                          (sin(_waveController.value * 2 * pi + phase) + 1) /
                              2;
                      final height = 8.0 + value * 28.0;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2.5),
                        width: 4,
                        height: height,
                        decoration: BoxDecoration(
                          color: AppTheme.gold.withValues(
                            alpha: 0.5 + value * 0.5,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),

            const Spacer(flex: 2),

            // ── Bottom controls ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Cancel button
                  OutlinedButton(
                    onPressed: _cancel,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                      foregroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontSize: 15),
                    ),
                  ),

                  // Stop button
                  GestureDetector(
                    onTap: _stopAndReturn,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        color: AppTheme.gold,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.stop_rounded,
                        color: Colors.black,
                        size: 28,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Caption ──
            Text(
              'Tap stop or pause for 4 seconds',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 12,
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
