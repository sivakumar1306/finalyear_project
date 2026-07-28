import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  static const List<_FaqItem> _faqs = [
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
                    itemCount: _faqs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final faq = _faqs[index];
                      return _buildFaqCard(index + 1, faq);
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
