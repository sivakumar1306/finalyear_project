import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../../../providers/ble_provider.dart';
import '../../../services/chat_api_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/app_typography.dart';
import '../../main_shell.dart';
import '../ring_scan_sheet.dart';
import 'home_card_shared.dart';
class HomeAiInsightSnippet extends StatefulWidget {
  const HomeAiInsightSnippet({super.key});

  @override
  State<HomeAiInsightSnippet> createState() => HomeAiInsightSnippetState();
}

class HomeAiInsightSnippetState extends State<HomeAiInsightSnippet> {
  static Map<String, dynamic>? _cache;
  static DateTime? _cacheTime;
  static const _cacheTtl = Duration(minutes: 5);

  Map<String, dynamic>? _data;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> reload({bool force = false}) async {
    await _load(force: force);
  }

  Future<void> _load({bool force = false}) async {
    if (force) {
      _cache = null;
      _cacheTime = null;
    }
    final isFresh =
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheTtl;
    if (!force &&
        _cache != null &&
        isFresh &&
        (_cache!['days_used'] as num? ?? 0) > 0) {
      if (mounted) setState(() => _data = _cache);
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      final result = await ChatApiService.getInsights();
      final headlineParts = result['headline_parts'] as List?;
      final hasHeadline = headlineParts != null && headlineParts.isNotEmpty;
      if (result['error'] == null &&
          hasHeadline &&
          (result['days_used'] as num? ?? 0) > 0) {
        _cache = result;
        _cacheTime = DateTime.now();
      }
      if (mounted) setState(() => _data = result);
    } catch (_) {
      // Silent — supplementary snippet, keep previous state or clear on force
      if (force && mounted) setState(() => _data = null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final headlineParts = _data?['headline_parts'] as List?;
    final subtext = _data?['subtext'] as String?;
    final hasHeadline = headlineParts != null && headlineParts.isNotEmpty;

    if (_loading && !hasHeadline) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SizedBox(
          height: 14,
          width: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: Color(0x4DFFFFFF),
          ),
        ),
      );
    }
    if (!hasHeadline || _data?['error'] != null) {
      return const SizedBox.shrink();
    }

    final headline = headlineParts
        .map((p) => (p as Map)['text'] as String? ?? '')
        .join();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: ShrinkButton(
        onTap: () {
          final prompt = 'Can you give me more details about this summary: "$headline"?';
          Navigator.of(context).push(buildAiAssistRoute(initialPrompt: prompt));
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.goldGlow,
                border: Border.all(
                  color: AppTheme.gold.withValues(alpha: 0.55),
                  width: 1.2,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome_rounded,
                        color: AppTheme.gold,
                        size: 13,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'AI SUMMARY',
                        style: AppTypography.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.18 * 10,
                          color: AppTheme.gold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    headline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.inter(
                      fontSize: 19,
                      fontWeight: FontWeight.w400,
                      height: 1.30,
                      letterSpacing: -0.02 * 19,
                      color: Colors.white,
                    ),
                  ),
                  if (subtext != null && subtext.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      subtext,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w400,
                        height: 1.50,
                        letterSpacing: 0.02 * 12.5,
                        color: Colors.white.withValues(alpha: 0.52),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Fall prediction banner ────────────────────────────────────────────────────
// Mirrors the hero-card alert styling already established on the Fall Detection
// screen (gradient + accent border, not the ambient-orb metric-card look) so the
// same alert appears consistent whether it's seen here or after drilling in.

class FallPredictionBanner extends StatelessWidget {
  final String tier;
  final String message;
  final int? smsSecondsRemaining;
  final bool smsHasPermission;
  final VoidCallback onCardTap;
  final VoidCallback onPrimaryAction;
  final VoidCallback onIgnore;

  const FallPredictionBanner({
    super.key,
    this.tier = 'low',
    required this.message,
    this.smsSecondsRemaining,
    this.smsHasPermission = true,
    required this.onCardTap,
    required this.onPrimaryAction,
    required this.onIgnore,
  });

  @override
  Widget build(BuildContext context) {
    final countdown = smsSecondsRemaining;
    final isHigh = tier == 'high' || countdown != null;
    final accent = isHigh ? AppTheme.hrColor : AppTheme.tempColor;
    
    final title = countdown != null
        ? 'Emergency SMS in ${countdown}s'
        : (isHigh ? 'You might fall soon...' : 'We are concerned ...');
        
    final body = countdown != null
        ? (!smsHasPermission
              ? 'SMS permission is missing — grant it so contacts can be alerted automatically. Open the app settings if needed.'
              : 'SMS will be sent to all emergency contacts in $countdown seconds. Tap Cancel if you are okay.')
        : (isHigh 
              ? 'We have detected multiple signs that you might fall down in the next 2-3 minutes. Take a seat and contact your caretaker.'
              : message);

    return ShrinkButton(
      onTap: onCardTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.25), width: 0.5),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [accent.withValues(alpha: 0.30), AppTheme.card],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  countdown != null ? 'EMERGENCY SMS' : 'LIKELY FALL ALERT',
                  style: inter(
                    11,
                    weight: FontWeight.w700,
                    color: accent,
                    letterSpacing: 1.0,
                  ),
                ),
                const Spacer(),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(title, style: inter(20, weight: FontWeight.w600)),
            const SizedBox(height: 10),
            Text(
              body,
              style: inter(
                13,
                color: Colors.white.withValues(alpha: 0.85),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      onPressed: onPrimaryAction,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.14),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      child: Text(
                        isHigh && countdown == null ? 'Alert emergency contact' : 'Take action',
                        style: inter(14, weight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                if (!isHigh || countdown != null)
                  TextButton(
                    onPressed: onIgnore,
                    child: Text(
                      countdown != null ? 'Cancel SMS' : 'ignore',
                      style: inter(
                        14,
                        weight: FontWeight.w600,
                        color: AppTheme.danger,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class FallEventBanner extends StatelessWidget {
  final int countdown;
  final VoidCallback onCardTap;
  final VoidCallback onCancel;

  const FallEventBanner({
    super.key,
    required this.countdown,
    required this.onCardTap,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return ShrinkButton(
      onTap: onCardTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.hrColor.withValues(alpha: 0.25), width: 0.5),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.hrColor.withValues(alpha: 0.40), AppTheme.card],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'FALL PREDICTION',
                  style: inter(
                    11,
                    weight: FontWeight.w700,
                    color: AppTheme.hrColor,
                    letterSpacing: 1.0,
                  ),
                ),
                const Spacer(),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('We have detected a fall', style: inter(20, weight: FontWeight.w600)),
            const SizedBox(height: 10),
            Text(
              'We have detected that you may have potentially fallen. Notifying emergency contacts & services in $countdown seconds',
              style: inter(
                13,
                color: Colors.white.withValues(alpha: 0.85),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Dialing emergency contact ...',
                  style: inter(13, color: Colors.white.withValues(alpha: 0.85)),
                ),
                ElevatedButton(
                  onPressed: onCancel,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: Text('Cancel', style: inter(14, weight: FontWeight.w500)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shrink press animation ────────────────────────────────────────────────────

class ShrinkButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const ShrinkButton({
    super.key,required this.child, this.onTap});

  @override
  State<ShrinkButton> createState() => ShrinkButtonState();
}

class ShrinkButtonState extends State<ShrinkButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) {
      return widget.child;
    }
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap!();
      },
      onTapCancel: () => setState(() => _pressed = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 80),
        opacity: _pressed ? 0.88 : 1.0,
        child: widget.child,
      ),
    );
  }
}

// ── Device pill ───────────────────────────────────────────────────────────────

class DevicePill extends StatelessWidget {
  final BleProvider ble;
  const DevicePill({
    super.key,required this.ble});

  @override
  Widget build(BuildContext context) {
    final connected = ble.isConnected;
    final reconnecting = ble.isReconnecting;
    final battery = ble.battery;

    return GestureDetector(
      onTap: () => showRingScanSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: kCardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kCardBorder, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (reconnecting)
              const SizedBox(
                width: 7,
                height: 7,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AppTheme.gold,
                ),
              )
            else
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: connected
                      ? AppTheme.success
                      : Colors.white.withValues(alpha: 0.2),
                ),
              ),
            if (battery >= 0) ...[
              const SizedBox(width: 6),
              Icon(
                battery > 60
                    ? Icons.battery_full_rounded
                    : battery > 30
                    ? Icons.battery_3_bar_rounded
                    : Icons.battery_1_bar_rounded,
                color: battery > 20
                    ? Colors.white.withValues(alpha: 0.5)
                    : AppTheme.danger,
                size: 14,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Device connected celebration banner ─────────────────────────────────────
// Full-width expansion of DevicePill shown briefly after a connect.
// Reuses DevicePill tokens (kCardBg/kCardBorder/20 radius/inter) — no new
// design language. Compact pill stays in place; this banner drops to the
// next line, holds, then collapses away.

class DeviceConnectedBanner extends StatelessWidget {
  final BleProvider ble;
  const DeviceConnectedBanner({super.key, required this.ble});

  @override
  Widget build(BuildContext context) {
    final battery = ble.battery;
    final name = ble.deviceName.isNotEmpty ? ble.deviceName : 'Ring';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kCardBorder, width: 0.5),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 16,
            color: AppTheme.success,
          ),
          const SizedBox(width: 8),
          Text(
            'Connected',
            style: inter(13, weight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              style: inter(12, weight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (battery >= 0) ...[
            Icon(
              battery > 60
                  ? Icons.battery_full_rounded
                  : battery > 30
                  ? Icons.battery_3_bar_rounded
                  : Icons.battery_1_bar_rounded,
              color: battery > 20
                  ? Colors.white.withValues(alpha: 0.5)
                  : AppTheme.danger,
              size: 14,
            ),
            const SizedBox(width: 4),
            Text(
              '$battery%',
              style: inter(11, color: Colors.white.withValues(alpha: 0.5)),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Connect hint ──────────────────────────────────────────────────────────────

class ConnectHint extends StatelessWidget {
  final bool compact;
  const ConnectHint({
    super.key,this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Align(
        alignment: Alignment.centerRight,
        child: Icon(
          Icons.bluetooth_disabled_rounded,
          size: 16,
          color: Colors.white.withValues(alpha: 0.2),
        ),
      );
    }
    return SizedBox(
      height: 26,
      child: Row(
        children: [
          Icon(
            Icons.bluetooth_disabled_rounded,
            size: 11,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(width: 5),
          Text(
            'Connect Ring to Track',
            style: inter(10, color: Colors.white.withValues(alpha: 0.3)),
          ),
        ],
      ),
    );
  }
}

// ── Edit Cards button ─────────────────────────────────────────────────────────

class EditCardsButton extends StatelessWidget {
  final VoidCallback onTap;

  const EditCardsButton({
    super.key,required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ShrinkButton(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              width: 85,
              height: 29,
              decoration: BoxDecoration(
                color: kBtnBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  'Edit Cards',
                  style: inter(
                    11,
                    weight: FontWeight.w500,
                    color: AppTheme.gold,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


