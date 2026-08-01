import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Shared backdrop for the auth screens (forgot password flow): soft gold
/// ambient glows per the Figma design — Ellipse 7 (280x200, gold 5% alpha,
/// gaussian blur 40) top-right and Ellipse 8 (450x320, gold 2.5% alpha,
/// blur 50) bottom-left — over the app's #050505 background.
class AuthBackground extends StatelessWidget {
  final Widget child;

  const AuthBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      body: Stack(
        children: [
          Positioned(
            right: -128,
            top: -100,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                width: 280,
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.elliptical(140, 100)),
                  gradient: const RadialGradient(
                    colors: [Color(0x0DC9A86E), Color(0x00C9A86E)],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: -227,
            bottom: -160,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: Container(
                width: 450,
                height: 320,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.elliptical(225, 160)),
                  gradient: const RadialGradient(
                    colors: [Color(0x06C9A86E), Color(0x00C9A86E)],
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Frosted-glass auth input: uppercase label above a 47px glass pill field —
/// blur 14, translucent white fill, hairline border, radius 18 — matching the
/// Figma "Forgot Password" screen.
class AuthGlassField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final Widget? suffix;

  const AuthGlassField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0x61FFFFFF),
            fontSize: 10,
            letterSpacing: 1.8,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              height: 47,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0x0AFFFFFF),
                border: Border.all(color: const Color(0x14FFFFFF), width: 0.5),
                borderRadius: BorderRadius.circular(18),
              ),
              child: TextField(
                controller: controller,
                obscureText: obscure,
                keyboardType: keyboardType,
                textInputAction: textInputAction,
                onChanged: onChanged,
                style: const TextStyle(color: Color(0xEDFFFFFF), fontSize: 13),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: const TextStyle(color: Color(0x3DFFFFFF)),
                  suffixIcon: suffix,
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Primary gold pill CTA used across the auth screens: #C9A86E fill, 47px
/// tall, fully pill-shaped, dark semibold label.
class AuthGoldButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  const AuthGoldButton({
    super.key,
    required this.label,
    this.loading = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 47,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFC9A86E),
          foregroundColor: const Color(0xED050505),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xED050505),
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
