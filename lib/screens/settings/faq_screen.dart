import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  // Mixed list of FAQ text entries and standalone image entries so a picture
  // (the charging-indicator diagram) can sit between two questions without
  // being attached to either one's answer text. Numbering below only counts
  // _FaqItem entries, skipping _FaqImage ones, so the image doesn't throw
  // off the "1. / 2. / 3." sequence.
  static const List<Object> _entries = [
    _FaqItem(
      question: 'Why do I need a Sundr account?',
      answer:
          'Your account keeps your health data safe and lets you get to it '
          'from any device. If you switch phones or reinstall the app, '
          "everything is still there when you sign back in. It also lets "
          'you share readings with family members, back up your medical '
          'records securely, and pick up right where you left off with the '
          'AI chat. Nothing about you is tied to the ring itself, so your '
          'data stays with you, not the device.',
    ),
    _FaqImage(assetPath: 'ring_charge.png'),
    _FaqItem(
      question: 'How to charge a ring?',
      answer:
          'Use a compliant mobile phone charger or computer USB port to '
          'connect a charging cable or charging case to charge the ring. '
          'When the ring is charging, the red light indicates that it is '
          'charging, and the green light indicates that the battery is '
          'fully charged.',
    ),
    _FaqItem(
      question:
          'After downloading the app, cannot find the ring Bluetooth signal?',
      answer:
          'By default, the ring is turned off when it leaves the factory. '
          'After unpacking, it needs to be charged and activated for the '
          'first time. When charging is activated, the charging indicator '
          'light on the ring will display red, indicating that the ring has '
          'been turned on. For first-time use, please keep charging for at '
          'least 1 hour until the charging indicator light on the ring '
          'turns green',
    ),
    _FaqItem(
      question:
          "Why is my heart rate or blood pressure reading different from my clinic's monitor?",
      answer:
          'Small differences are normal. Your ring measures continuously '
          "while you go about your day, so readings change with movement, "
          'stress, temperature, and how you\'re wearing it. Clinic monitors '
          'give you a single snapshot in a controlled setting. Use your '
          'ring data to spot trends over time, not as a replacement for '
          'medical devices.',
    ),
    _FaqItem(
      question: 'Can I wear my ring in the shower or while swimming?',
      answer:
          'Sure, the ring has 5ATM waterproof performance. But please try '
          'not to use it in complex environments such as hot springs or '
          'seawater. If the ring comes into contact with seawater, please '
          'rinse it with fresh water as soon as possible to avoid corrosion '
          'of the metal material on the ring caused by the salt in '
          'seawater, which may lead to poor contact of the ring charging '
          'position.',
    ),
    _FaqItem(
      question: 'Is my health data private?',
      answer:
          'Yes. Your data is encrypted on your phone and on our servers. '
          'We never sell it or share it with advertisers.',
    ),
    _FaqItem(
      question: 'Can I rely on the AI chat for medical advice?',
      answer:
          "No. The AI chat is there to help you understand your own data. "
          "It's not a doctor and can't diagnose, prescribe, or replace "
          'clinical advice. If something feels off or a reading worries '
          'you, talk to a healthcare professional. For anything urgent, '
          'contact emergency services.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      body: Stack(
        children: [
          // Ambient glow
          Positioned(
            left: 223,
            top: -100,
            child: Container(
              width: 280,
              height: 200,
              decoration: BoxDecoration(
                color: const Color(0xFFC9A86E).withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(200),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 26),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.25),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(100),
                        child: Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.04),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                              width: 0.5,
                            ),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Color(0xFFD9D9D9),
                            size: 16,
                          ),
                        ),
                      ),
                      Text(
                        "FAQ's",
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.005,
                        ),
                      ),
                      const SizedBox(width: 36, height: 36),
                    ],
                  ),
                ),

                // FAQ list
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    itemCount: _entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final entry = _entries[index];

                      if (entry is _FaqImage) {
                        return _buildImageCard(entry);
                      }

                      final faq = entry as _FaqItem;
                      // Number only counts _FaqItem entries up to and
                      // including this one, so the image in between doesn't
                      // break the 1/2/3 sequence.
                      final number = _entries
                          .sublist(0, index + 1)
                          .whereType<_FaqItem>()
                          .length;
                      return _buildFaqCard(number, faq);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageCard(_FaqImage image) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.asset(image.assetPath, fit: BoxFit.contain),
      ),
    );
  }

  Widget _buildFaqCard(int number, _FaqItem faq) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$number. ${faq.question}',
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              height: 1.5,
              letterSpacing: -0.005,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            faq.answer,
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 13.5,
              fontWeight: FontWeight.w400,
              height: 1.5,
              letterSpacing: -0.005,
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqItem {
  final String question;
  final String answer;

  const _FaqItem({required this.question, required this.answer});
}

class _FaqImage {
  final String assetPath;

  const _FaqImage({required this.assetPath});
}
