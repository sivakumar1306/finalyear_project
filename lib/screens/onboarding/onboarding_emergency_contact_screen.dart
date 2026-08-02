import 'package:flutter/material.dart';
import '../../models/onboarding_data.dart';
import 'onboarding_shell.dart';
import 'pair_ring_screen.dart';

class OnboardingEmergencyContactScreen extends StatefulWidget {
  final OnboardingData data;
  const OnboardingEmergencyContactScreen({super.key, required this.data});

  @override
  State<OnboardingEmergencyContactScreen> createState() => _OnboardingEmergencyContactScreenState();
}

class _OnboardingEmergencyContactScreenState extends State<OnboardingEmergencyContactScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.data.emergencyContactName);
    _phoneCtrl = TextEditingController(text: widget.data.emergencyContactPhone);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  bool _isValid() {
    return _nameCtrl.text.trim().isNotEmpty && _phoneCtrl.text.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingShell(
      step: 6,
      totalSteps: 6,
      data: widget.data,
      canContinue: _isValid(),
      buttonLabel: 'Finish',
      onContinue: () {
        widget.data.emergencyContactName = _nameCtrl.text.trim();
        widget.data.emergencyContactPhone = _phoneCtrl.text.trim();
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => PairRingScreen(data: widget.data),
          ),
          (_) => false,
        );
      },
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            onboardingHeader(
              'STEP 6 OF 6',
              'Set an ',
              'Emergency Contact',
              '',
              'This contact will be used automatically anywhere in the app that requires one, like for fall detection.',
            ),
            const Spacer(),
            TextField(
              controller: _nameCtrl,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
              decoration: const InputDecoration(
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: kGold, width: 2),
                ),
                hintText: 'Contact Name',
                hintStyle: TextStyle(color: Colors.white24, fontSize: 22),
              ),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _phoneCtrl,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.phone,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
              decoration: const InputDecoration(
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: kGold, width: 2),
                ),
                hintText: 'Phone Number',
                hintStyle: TextStyle(color: Colors.white24, fontSize: 22),
              ),
            ),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }
}
