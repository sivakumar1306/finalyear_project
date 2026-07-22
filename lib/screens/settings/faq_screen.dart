import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

class FaqScreen extends StatefulWidget {
  const FaqScreen({super.key});

  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  int? _expandedIndex;

  static const List<_FaqItem> _faqs = [
    _FaqItem(
      icon: Icons.bluetooth_rounded,
      question: 'How do I connect my ring?',
      answer:
          'Go to Settings and tap "Find Device" or navigate to the Device Bind '
          'screen from the home page. Make sure Bluetooth is enabled on your '
          'phone and the ring is charged. The app will automatically scan for '
          'nearby rings — tap your ring\'s name to pair.',
    ),
    _FaqItem(
      icon: Icons.battery_charging_full_rounded,
      question: 'How long does the battery last?',
      answer:
          'On a full charge the ring typically lasts 3–5 days depending on '
          'usage. Continuous heart-rate monitoring and SpO₂ tracking will '
          'consume more power. Place the ring on the charging dock and ensure '
          'the contacts align — a full charge takes about 1.5 hours.',
    ),
    _FaqItem(
      icon: Icons.monitor_heart_outlined,
      question: 'How does heart rate monitoring work?',
      answer:
          'The ring uses PPG (photoplethysmography) sensors on the inner band '
          'to measure your heart rate continuously. For the most accurate '
          'readings, wear the ring snugly on your index or middle finger and '
          'avoid excessive movement during measurement.',
    ),
    _FaqItem(
      icon: Icons.nightlight_round,
      question: 'How is my sleep tracked?',
      answer:
          'Sleep tracking starts automatically when the ring detects you are '
          'asleep based on movement and heart-rate patterns. It classifies '
          'your sleep into Awake, Light, and Deep stages. You can view a '
          'detailed breakdown each morning on the Sleep screen.',
    ),
    _FaqItem(
      icon: Icons.water_drop_outlined,
      question: 'Is the ring waterproof?',
      answer:
          'The ring has an IP68 rating, meaning it is resistant to dust and '
          'can withstand submersion in fresh water up to 1.5 metres for '
          '30 minutes. However, it is not recommended for swimming, diving, '
          'or exposure to hot water or chemicals.',
    ),
    _FaqItem(
      icon: Icons.straighten_rounded,
      question: 'How do I find my ring size?',
      answer:
          'Use the sizing kit included in your package. Wear the sample rings '
          'on different fingers for at least 24 hours to find the best fit. '
          'The ring should be snug but comfortable — not so tight that it '
          'leaves a mark, and not so loose that it slides easily.',
    ),
    _FaqItem(
      icon: Icons.sync_rounded,
      question: 'Why isn\'t my data syncing?',
      answer:
          'Make sure your ring is connected via Bluetooth and is within '
          'range of your phone. Try pulling down to refresh on the Home '
          'screen. If the issue persists, toggle Bluetooth off and on, then '
          'reopen the app. Keeping the app running in the background also '
          'helps maintain a stable connection.',
    ),
    _FaqItem(
      icon: Icons.health_and_safety_rounded,
      question: 'What is HRV and why does it matter?',
      answer:
          'Heart Rate Variability (HRV) measures the variation in time '
          'between heartbeats. A higher HRV generally indicates better '
          'cardiovascular fitness and stress resilience. The ring measures '
          'HRV during sleep for the most consistent and accurate readings.',
    ),
    _FaqItem(
      icon: Icons.system_update_rounded,
      question: 'How do I update the firmware?',
      answer:
          'Go to Settings → Firmware Upgrade. If an update is available you '
          'will see a prompt to download and install it. Keep the ring on the '
          'charger and near your phone during the update. Do not close the '
          'app until the update is complete.',
    ),
    _FaqItem(
      icon: Icons.delete_outline_rounded,
      question: 'How do I reset my ring?',
      answer:
          'Navigate to Settings → Account & System Settings → Factory Reset. '
          'This will erase all data stored on the ring and restore it to its '
          'default state. Your health data in the app will not be affected.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "FAQ's",
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
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),

            // Header illustration area
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A1508), Color(0xFF111111)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.goldBorder, width: 0.5),
              ),
              child: Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppTheme.gold.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.help_outline_rounded,
                        color: AppTheme.gold, size: 28),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Frequently Asked Questions',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Find answers to common questions about\nyour ring and the app.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: AppTheme.textSec,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),
            _sectionLabel('GENERAL'),
            const SizedBox(height: 10),

            // FAQ list
            Container(
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: List.generate(_faqs.length * 2 - 1, (i) {
                  if (i.isOdd) {
                    return const Divider(
                        height: 1, color: AppTheme.div, indent: 0, endIndent: 0);
                  }
                  final index = i ~/ 2;
                  return _buildFaqTile(index);
                }),
              ),
            ),

            const SizedBox(height: 28),

            // Contact support card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.card2,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.mail_outline_rounded,
                        color: Color(0xFFAAAAAA), size: 20),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Still have questions?",
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Contact our support team for help.',
                    style: GoogleFonts.inter(
                      color: AppTheme.textSec,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        // TODO: launch email / support
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.gold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Contact Support',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildFaqTile(int index) {
    final faq = _faqs[index];
    final isExpanded = _expandedIndex == index;

    return InkWell(
      onTap: () {
        setState(() {
          _expandedIndex = isExpanded ? null : index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        color: isExpanded ? AppTheme.card2 : Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: isExpanded
                        ? AppTheme.gold.withOpacity(0.12)
                        : AppTheme.card2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    faq.icon,
                    color: isExpanded ? AppTheme.gold : const Color(0xFFAAAAAA),
                    size: 17,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    faq.question,
                    style: GoogleFonts.inter(
                      color: isExpanded ? Colors.white : Colors.white,
                      fontSize: 14,
                      fontWeight:
                          isExpanded ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.keyboard_arrow_down_rounded,
                      color: AppTheme.textSec, size: 22),
                ),
              ],
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(left: 48, top: 10, right: 4),
                child: Text(
                  faq.answer,
                  style: GoogleFonts.inter(
                    color: AppTheme.textSec,
                    fontSize: 13,
                    height: 1.55,
                  ),
                ),
              ),
              crossFadeState: isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: GoogleFonts.inter(
          color: AppTheme.textSec,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
        ),
      );
}

class _FaqItem {
  final IconData icon;
  final String question;
  final String answer;

  const _FaqItem({
    required this.icon,
    required this.question,
    required this.answer,
  });
}
