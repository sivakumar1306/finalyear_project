import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/supabase_service.dart';
import '../../widgets/glass_back_button.dart';
import 'auth_background.dart';
import 'reset_password_screen.dart';

/// Step 2 of the password-recovery flow — enter the recovery code
/// sent to the registered email. Supports both 6-digit and 8-digit codes,
/// auto-advances, supports direct pasting, and offers a "Paste Code" button.
class RecoveryCodeScreen extends StatefulWidget {
  final String email;

  const RecoveryCodeScreen({super.key, required this.email});

  @override
  State<RecoveryCodeScreen> createState() => _RecoveryCodeScreenState();
}

class _RecoveryCodeScreenState extends State<RecoveryCodeScreen> {
  int _codeLength = 6;
  late List<TextEditingController> _controllers;
  late List<FocusNode> _focusNodes;
  bool _loading = false;
  bool _resending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initControllers(_codeLength);
  }

  void _initControllers(int length) {
    _controllers = List.generate(length, (_) => TextEditingController());
    _focusNodes = List.generate(length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _code => _controllers.map((c) => c.text).join();

  void _onDigitChanged(int index, String value) {
    setState(() => _error = null);

    final cleanDigits = value.replaceAll(RegExp(r'\D'), '');
    if (cleanDigits.length > 1) {
      _fillFromPastedText(cleanDigits);
      return;
    }

    if (value.isNotEmpty && index < _codeLength - 1) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }

    if (_code.length == _codeLength) {
      _verify();
    }
  }

  void _fillFromPastedText(String text) {
    final clean = text.replaceAll(RegExp(r'\D'), '');
    if (clean.isEmpty) return;

    final targetLen = clean.length == 6 ? 6 : 8;
    if (_codeLength != targetLen) {
      setState(() {
        _codeLength = targetLen;
        _initControllers(targetLen);
      });
    }

    for (int i = 0; i < _codeLength; i++) {
      if (i < clean.length) {
        _controllers[i].text = clean[i];
      } else {
        _controllers[i].clear();
      }
    }

    if (clean.length >= _codeLength) {
      _focusNodes[_codeLength - 1].unfocus();
      _verify();
    } else {
      _focusNodes[clean.length.clamp(0, _codeLength - 1)].requestFocus();
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isNotEmpty) {
      _fillFromPastedText(text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Code pasted from clipboard.')),
        );
      }
    } else {
      setState(() => _error = 'Clipboard is empty.');
    }
  }

  void _toggleLength(int newLen) {
    if (_codeLength == newLen) return;
    setState(() {
      _codeLength = newLen;
      _initControllers(newLen);
      _error = null;
    });
  }

  Future<void> _verify() async {
    final code = _code.trim();
    if (code.length < 6) {
      setState(() => _error = 'Please enter the complete recovery code.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SupabaseService.verifyRecoveryCode(widget.email, code);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e.toString().replaceAll('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      await SupabaseService.resetPassword(widget.email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recovery code resent.')),
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e.toString().replaceAll('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final boxWidth = _codeLength == 8 ? 36.0 : 46.0;

    return AuthBackground(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  GlassBackButton(),
                  SizedBox(width: 36),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Enter Recovery Code',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            letterSpacing: -0.38,
                            height: 1.3,
                          ),
                        ),
                        // Segmented toggle for 6 or 8 digits
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: const Color(0x1AFFFFFF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              _LengthChip(
                                label: '6-digit',
                                selected: _codeLength == 6,
                                onTap: () => _toggleLength(6),
                              ),
                              _LengthChip(
                                label: '8-digit',
                                selected: _codeLength == 8,
                                onTap: () => _toggleLength(8),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'We sent a recovery code to ${widget.email}',
                      style: const TextStyle(
                        color: Color(0x85FFFFFF),
                        fontSize: 12.5,
                        letterSpacing: 0.25,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Code Boxes Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(_codeLength, (i) {
                        return _CodeBox(
                          controller: _controllers[i],
                          focusNode: _focusNodes[i],
                          width: boxWidth,
                          onChanged: (v) => _onDigitChanged(i, v),
                        );
                      }),
                    ),

                    const SizedBox(height: 18),

                    // Quick Paste & Resend Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: _pasteFromClipboard,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0x14FFFFFF),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: const Color(0x26FFFFFF), width: 0.8),
                            ),
                            child: Row(
                              children: const [
                                Icon(Icons.content_paste_rounded,
                                    color: Color(0xFFC9A86E), size: 14),
                                SizedBox(width: 6),
                                Text(
                                  'Paste Code',
                                  style: TextStyle(
                                    color: Color(0xFFC9A86E),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            const Text(
                              "Didn't get it? ",
                              style: TextStyle(
                                color: Color(0x85FFFFFF),
                                fontSize: 12.5,
                              ),
                            ),
                            GestureDetector(
                              onTap: _resending ? null : _resend,
                              child: _resending
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFFC9A86E),
                                      ),
                                    )
                                  : const Text(
                                      'Resend',
                                      style: TextStyle(
                                        color: Color(0xFFC9A86E),
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 18),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: AuthGoldButton(
                label: 'Verify Code',
                loading: _loading,
                onPressed: _verify,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LengthChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LengthChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFC9A86E) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : const Color(0x85FFFFFF),
            fontSize: 10.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _CodeBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final double width;
  final ValueChanged<String> onChanged;

  const _CodeBox({
    required this.controller,
    required this.focusNode,
    required this.width,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          width: width,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0x0AFFFFFF),
            border: Border.all(color: const Color(0x14FFFFFF), width: 0.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: false,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xEDFFFFFF), fontSize: 18),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8), // Allow full code paste
            ],
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              isDense: true,
            ),
            onChanged: onChanged,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
          ),
        ),
      ),
    );
  }
}
