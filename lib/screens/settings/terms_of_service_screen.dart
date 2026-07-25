import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Terms of Service',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Last updated: July 25, 2026',
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSec),
            ),
            const SizedBox(height: 24),
            _section(
              title: 'Acceptance of Terms',
              body:
                  'By creating an account and using the SUNDR app, you agree to these '
                  'Terms of Service. If you do not agree, please discontinue use of the app.',
            ),
            _section(
              title: 'The Service',
              body:
                  'SUNDR provides a companion app for your smart ring, offering health and '
                  'wellness tracking, insights, and AI-powered analysis. Features that rely '
                  'on ring data require an active, paired ring.',
            ),
            _section(
              title: 'Not Medical Advice',
              body:
                  'SUNDR is intended for general wellness purposes only and is not a medical '
                  'device. Information provided by the app should not be used to diagnose, '
                  'treat, cure, or prevent any disease. Always consult a qualified healthcare '
                  'provider with any health concerns.',
            ),
            _section(
              title: 'Your Account',
              body:
                  'You are responsible for maintaining the confidentiality of your account '
                  'credentials and for all activity that occurs under your account.',
            ),
            _section(
              title: 'Acceptable Use',
              body:
                  'You agree not to misuse the app, attempt to reverse engineer the ring '
                  'firmware or app, or use the service in any way that violates applicable '
                  'law.',
            ),
            _section(
              title: 'Changes to the Service',
              body:
                  'We may update, modify, or discontinue features of the app at any time. '
                  'We will make reasonable efforts to notify you of material changes.',
            ),
            _section(
              title: 'Limitation of Liability',
              body:
                  'SUNDR is provided "as is" without warranties of any kind. To the fullest '
                  'extent permitted by law, we are not liable for any indirect, incidental, '
                  'or consequential damages arising from your use of the app.',
            ),
            _section(
              title: 'Contact Us',
              body:
                  'If you have questions about these Terms, reach out to us through the '
                  'support options available in Settings.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _section({required String title, required String body}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.65),
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}
