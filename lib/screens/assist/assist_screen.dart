import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class AssistScreen extends StatelessWidget {
  const AssistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.goldBorder,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.gold.withValues(alpha: 0.3), width: 1),
              ),
              child: const Icon(Icons.smart_toy_rounded, color: AppTheme.gold, size: 40),
            ),
            const SizedBox(height: 20),
            const Text(
              'AI Health Assistant',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Coming soon',
              style: TextStyle(color: AppTheme.textSec, fontSize: 15),
            ),
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.div),
              ),
              child: const Text(
                'Your personal AI health coach will analyze\nyour vitals and provide insights here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSec, fontSize: 13, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
