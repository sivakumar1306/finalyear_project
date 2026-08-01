import 'package:flutter/material.dart';
import '../../models/onboarding_data.dart';
import '../../services/supabase_service.dart';

class PairRingScreen extends StatefulWidget {
  final OnboardingData data;
  const PairRingScreen({super.key, required this.data});

  @override
  State<PairRingScreen> createState() => _PairRingScreenState();
}

class _PairRingScreenState extends State<PairRingScreen> {
  bool _saving = false;

  Future<void> _saveProfile() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    setState(() => _saving = true);
    try {
      await SupabaseService.upsertProfile(
        userId: user.id,
        fullName: widget.data.name,
        age: widget.data.age,
        gender: widget.data.gender,
        heightCm: widget.data.heightCm,
        weightKg: widget.data.weightKg,
      );
    } catch (_) {}
    setState(() => _saving = false);
  }

  Future<void> _pairNow() async {
    await _saveProfile();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
    Navigator.pushNamed(context, '/device-bind');
  }

  Future<void> _doLater() async {
    await _saveProfile();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(5, (i) => Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == 4 ? 20 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == 4
                                ? const Color(0xFFC9A86E)
                                : Colors.white24,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        )),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _saving ? null : _doLater,
                    child: const Text('SKIP',
                        style: TextStyle(color: Colors.white54, fontSize: 13, letterSpacing: 1)),
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    const Text('STEP 6 OF 6',
                        style: TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                            letterSpacing: 1.5)),
                    const SizedBox(height: 10),
                    RichText(
                      text: const TextSpan(
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold),
                        children: [
                          TextSpan(text: 'Time to meet your '),
                          TextSpan(
                              text: 'ring',
                              style: TextStyle(color: Color(0xFFC9A86E))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Pair now to start tracking, or do it later from Settings.',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                    const Spacer(),
                    Center(
                      child: Image.asset('ring.png', height: 220),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
            // Buttons
            if (_saving)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: Color(0xFFC9A86E)),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _pairNow,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC9A86E),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                      elevation: 0,
                    ),
                    child: const Text('Pair my ring',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _doLater,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                    ),
                    child: const Text("I'll do this later",
                        style: TextStyle(color: Colors.white, fontSize: 15)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
