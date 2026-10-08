import 'package:flutter/material.dart';

import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';
import '../../theme/app_theme.dart';

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  // Mixed list of FAQ text entries and standalone image entries so a picture
  // can sit between two questions without being attached to either one's
  // answer text. Numbering below only counts _FaqItem entries, skipping
  // _FaqImage ones, so the image doesn't throw off the "1. / 2. / 3." sequence.
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
    _FaqImage(assetPath: 'ring_bluetooth_indicator.webp'),
    _FaqItem(
      question:
          'Why does the ring always show disconnected when opening QRing?',
      answer:
          'Due to the consideration of saving system resources, some mobile '
          'phone systems may disable QRING that users have not set up '
          'background protection in the background. Therefore, please refer '
          "to the background protection guide and enable QRing's background "
          'protection function If QRing is already turned on and still '
          'shows disconnected, it is possible that the ring has shut down '
          'due to low battery. Please charge it before reconnecting.',
    ),
    _FaqImage(assetPath: 'ring_bluetooth_indicator.webp'),
    _FaqItem(
      question: "Why can't the ring be charged?",
      answer:
          '1.Use tooling to clean Cotton swab: Cotton swab is a very '
          'convenient cleaning tool that can be used to clean the dust from '
          'the charging port. Just turn the cotton swab gently to clean the '
          'surface dust.',
    ),
    _FaqImage(assetPath: 'charging_port_cotton_swab.webp'),
    _FaqItem(
      question: 'Toothpick cleaning method',
      answer:
          'If there is a lot of dust around the charging port, you can use '
          'a toothpick to clean it. But be careful not to use the toothpick '
          'too thick to avoid damaging the charging port.',
    ),
    _FaqImage(assetPath: 'charging_port_toothpick.webp'),
    _FaqItem(
      question: '2.Detergent',
      answer:
          'If the dust on the charging port is stubborn, you can use some '
          'detergent to clean it. But be careful to choose a mild cleaner '
          'to avoid damaging the ring. At the same time, pay attention to '
          'the amount and method of application when using detergent to '
          'avoid corrosion or damage to the charging port.',
    ),
    _FaqImage(assetPath: 'charging_port_detergent.webp'),
    _FaqItem(
      question: '3.Cautions',
      answer:
          'Pay attention the method and force when cleaning, do not use too '
          'rough methods to avoid damaging the charging port.If the '
          'charging port is damaged or cannot be cleaned, we recommend you '
          'to contact customer service for helping.',
    ),
    _FaqItem(
      question: 'How to charge a ring?',
      answer:
          'Use a compliant mobile phone charger or computer USB port to '
          'connect a charging cable or charging case to charge the ring. '
          'When the ring is charging, the red light indicates that it is '
          'charging, and the green light indicates that the battery is '
          'fully charged.',
    ),
    _FaqImage(assetPath: 'charging_indicator_states.webp'),
    _FaqItem(
      question: 'Is sleep data unable to synchronize or inaccurate?',
      answer:
          '(1) If the ring is not worn and enters sleep mode, QRing will '
          'not generate sleep data after the ring synchronizes with QRing '
          '(2) The ring records sleep data at night and cannot record '
          'sleep during the day (3) The user wears a ring and starts '
          'recording (deep sleep, light sleep, wakefulness, etc.) within '
          '30 minutes of lying down, and ends sleep monitoring after '
          'waking up. (4) All sleep records will be viewed on the QRing '
          'sleep interface after the ring is synchronized with QRing',
    ),
    _FaqImage(assetPath: 'sleep_stages_chart.webp'),
    _FaqItem(
      question:
          'There is a deviation between the entry and exit sleep time '
          'recorded in sleep records and personal feelings',
      answer:
          'The time of falling asleep and waking up is marked by changes '
          'in the physiological characteristics of the human body when '
          'entering and waking up from sleep. The sleep state is detected '
          'through sensors inside the ring, which may have a certain time '
          "deviation from one's actual perception.",
    ),
    _FaqItem(
      question: 'The sleep data will show a clear state in the middle',
      answer:
          'The human sleep process consists of various sleep states such '
          'as light sleep, deep sleep, and wakefulness In a conscious '
          "state, most people's body consciousness is still very vague, "
          'and users may not be aware of their tendency state, resulting '
          'in a deviation between personal feelings and ring detection '
          'and recording data.',
    ),
    _FaqItem(
      question:
          'Will playing with a phone while lying still be recognized as a '
          'sleep state?',
      answer:
          'Sleep detection is achieved through sensors on the ring that '
          'detect human activity characteristics. If a user maintains the '
          'same posture for a long time without moving, it may be '
          'recognized as entering a sleep state.',
    ),
    _FaqItem(
      question:
          "Why did I start walking, but the ring didn't start counting "
          'steps?',
      answer:
          'In order to reduce the step counting error of the ring caused '
          'by frequent hand activities such as typing on the keyboard and '
          'playing poker The ring is set with an initial value of 10, and '
          'only when the number of steps reaches 10 in a row, will the '
          'step counting officially begin. At the same time, the '
          'real-time step count in the QRing main interface will change.',
    ),
    _FaqItem(
      question:
          'Under what circumstances will data be automatically connected '
          'and synchronized?',
      answer:
          'After the user completes the first ring binding, when they '
          'open QRing again, the ring will automatically connect to QRing '
          'and start synchronizing data; At this point, the user does not '
          'need to take any action. If there is an inability to connect, '
          'please charge and check again to see if it can connect to '
          'QRing and synchronize data',
    ),
    _FaqItem(
      question: 'How to manually connect and synchronize data?',
      answer:
          'Clicking the sync button in the upper right corner of the app '
          'will automatically synchronize the current data of the ring.',
    ),
    _FaqItem(
      question: 'Can I wear a ring when taking a shower?',
      answer:
          'Sure, the ring has 5ATM waterproof performance. But please try '
          'not to use it in complex environments such as hot springs or '
          'seawater If the ring comes into contact with seawater, please '
          'rinse it with fresh water as soon as possible to avoid '
          'corrosion of the metal material on the ring caused by the salt '
          'in seawater, which may lead to poor contact of the ring '
          'charging position.',
    ),
    _FaqItem(
      question: 'What is the ambient temperature for using the ring?',
      answer:
          'The normal operating temperature for the ring is -10~+45 °C '
          '(14~113 °F). If stored or worn outside the normal temperature '
          'range for a long time, it will affect the lifespan and '
          'reliability of the ring, which may affect its normal use',
    ),
    _FaqItem(
      question: 'Unable to connect after the latest firmware upgrade?',
      answer:
          "After updating the firmware, the APP will synchronize the "
          "device's historical data with the server, which takes about "
          '3-5 seconds. It needs to wait for the data synchronization to '
          'complete before connecting to the ring.',
    ),
    _FaqItem(
      question: 'The correct direction for wearing a ring?',
      answer:
          'For optimal performance and accuracy, it is recommended that '
          'you wear the ring on the index finger of your non dominant '
          'hand. If you wear it on your middle and ring fingers, the '
          'heart rate sensor should be located on the palm of your hand, '
          'and the ring should be comfortably placed close to the skin at '
          'the base of your fingers. Please try to keep the inside of the '
          'ring dry when wearing it, and avoid soaking the skin of the '
          'finger wearing area with sweat or other liquids for a long '
          'time, which may cause skin damage',
    ),
    _FaqImage(assetPath: 'ring_wearing_direction.webp'),
    _FaqItem(
      question:
          'Will historical data be lost after losing or uninstalling the '
          'ring and reinstalling QRing?',
      answer:
          'If QRing is uninstalled and reinstalled, the data saved '
          'locally by QRing will be lost Recommend users to register for '
          'QRing ID and use it to log in to QRing',
    ),
    _FaqImage(assetPath: 'sundr_welcome.webp'),
    _FaqItem(
      question: 'How to use the camera function?',
      answer:
          'Maintain Bluetooth connection between the ring and the phone; '
          'Click the remote camera button in QRing; Gently shake the hand '
          'wearing the ring to complete the photo PS. For first-time use, '
          'it is necessary to follow the QRing prompt and allow '
          'permission to call the system camera;',
    ),
    _FaqItem(
      question: 'Why is the app unable to display health index?',
      answer:
          'The health index is obtained through comprehensive evaluation '
          'based on the sleep, exercise, stress, heart rate, and blood '
          'oxygen data collected by the ring. Among them, sleep data is '
          'the most basic data. If the wearing time is too short or there '
          'is no sleep data, the health index cannot be generated. We '
          'suggest that you continue to wear the ring to unlock your '
          'health index.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
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
                color: AppTheme.gold.withValues(alpha: 0.05),
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
                    children: [
                      const GlassBackButton(),
                      Expanded(
                        child: Text(
                          "FAQ's",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: AppTypography.inter(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.005,
                          ),
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
                    separatorBuilder: (_, _) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final entry = _entries[index];

                      if (entry is _FaqImage) {
                        return _buildImageCard(entry);
                      }

                      final faq = entry as _FaqItem;
                      // Number only counts _FaqItem entries up to and
                      // including this one, so images in between don't
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
            style: AppTypography.inter(
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
            style: AppTypography.inter(
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
