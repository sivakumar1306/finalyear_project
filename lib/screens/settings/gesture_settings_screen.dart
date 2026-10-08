import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/alarm_mode_provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/incident_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/glass_pill.dart';

/// Available actions that ring touch gestures can be mapped to.
enum GestureAction {
  answerCall,
  endCall,
  takePhoto,
  playPause,
  prayerDnd,
  none,
}

extension GestureActionExt on GestureAction {
  String get label {
    switch (this) {
      case GestureAction.answerCall:
        return 'Answer Incoming Call 📞';
      case GestureAction.endCall:
        return 'Decline / End Call 📵';
      case GestureAction.takePhoto:
        return 'Remote Camera Shutter 📸';
      case GestureAction.playPause:
        return 'Play / Pause Media 🎵';
      case GestureAction.prayerDnd:
        return 'Toggle Meditation DND';
      case GestureAction.none:
        return 'None';
    }
  }

  IconData get icon {
    switch (this) {
      case GestureAction.answerCall:
        return Icons.call_rounded;
      case GestureAction.endCall:
        return Icons.call_end_rounded;
      case GestureAction.takePhoto:
        return Icons.camera_alt_rounded;
      case GestureAction.playPause:
        return Icons.play_circle_fill_rounded;
      case GestureAction.prayerDnd:
        return Icons.self_improvement_rounded;
      case GestureAction.none:
        return Icons.block_rounded;
    }
  }
}

class GestureSettingsScreen extends StatefulWidget {
  const GestureSettingsScreen({super.key});

  @override
  State<GestureSettingsScreen> createState() => _GestureSettingsScreenState();
}

class _GestureSettingsScreenState extends State<GestureSettingsScreen> {
  final _ble = BleService();
  bool _loading = false;

  // Wrist-flip wake gesture
  bool _wristFlipEnabled = true;
  bool _isLeftHand = true;

  // Touch sensor
  bool _touchSensorEnabled = true;

  // Mapped Actions
  GestureAction _singleTapAction = GestureAction.answerCall;
  GestureAction _doubleTapAction = GestureAction.endCall;
  GestureAction _longPressAction = GestureAction.endCall;

  // Real-time Event Stream
  StreamSubscription<Map<String, dynamic>>? _eventSub;
  final List<Map<String, dynamic>> _gestureLog = [];
  DateTime? _lastSingleTapAt;
  static const _doubleTapWindow = Duration(milliseconds: 400);

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _eventSub = _ble.events.listen(_handleRingEvent);
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final bleProvider = context.read<BleProvider>();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _singleTapAction = _parseAction(prefs.getString('gesture_single_tap'), GestureAction.answerCall);
      _doubleTapAction = _parseAction(prefs.getString('gesture_double_tap'), GestureAction.endCall);
      _longPressAction = _parseAction(prefs.getString('gesture_long_press'), GestureAction.endCall);
      _isLeftHand = prefs.getBool('gesture_left_hand') ?? true;
    });

    if (bleProvider.isConnected) {
      setState(() => _loading = true);
      try {
        await bleProvider.loadGestureSetting();
        _wristFlipEnabled = bleProvider.gestureEnabled;

        final touchJson = await _ble.getTouchControlSetting();
        final map = jsonDecode(touchJson) as Map<String, dynamic>? ?? {};
        _touchSensorEnabled = (map['appType'] as int? ?? 0) != 0;
      } catch (e, st) {
        IncidentService.reportUnhandled(
          source: 'gesture_settings_screen',
          error: e,
          stackTrace: st,
          customMessage: 'load gesture/touch settings failed',
        );
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  GestureAction _parseAction(String? val, GestureAction fallback) {
    if (val == null) return fallback;
    return GestureAction.values.firstWhere((e) => e.name == val, orElse: () => fallback);
  }

  Future<void> _saveAction(String key, GestureAction action) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, action.name);
  }

  Future<void> _setWristFlip(bool enable) async {
    if (!mounted) return;
    setState(() => _wristFlipEnabled = enable);
    await context.read<BleProvider>().setGestureEnabled(enable, isLeft: _isLeftHand);
  }

  Future<void> _setHandOrientation(bool isLeft) async {
    final bleProvider = context.read<BleProvider>();
    if (!mounted) return;
    setState(() => _isLeftHand = isLeft);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('gesture_left_hand', isLeft);
    await bleProvider.setGestureEnabled(_wristFlipEnabled, isLeft: isLeft);
  }

  Future<void> _setTouchSensor(bool enable) async {
    if (!mounted) return;
    setState(() => _touchSensorEnabled = enable);
    await _ble.setTouchControlSetting(enable: enable, strength: 5);
  }

  void _handleRingEvent(Map<String, dynamic> event) {
    if (event['type'] != 'deviceNotification') return;
    final data = Map<String, dynamic>.from(event['data'] as Map);
    final dataType = data['dataType'] as int?;
    final loadData = (data['loadData'] as List?)?.cast<int>() ?? const <int>[];

    String gestureName = '';
    GestureAction? targetAction;

    if (dataType == 0x2d && loadData.length > 1) {
      final code = loadData[1];
      if (code == 3) {
        // Single tap or double tap synthesis
        final now = DateTime.now();
        if (_lastSingleTapAt != null && now.difference(_lastSingleTapAt!) <= _doubleTapWindow) {
          gestureName = 'Double Tap';
          targetAction = _doubleTapAction;
          _lastSingleTapAt = null;
        } else {
          _lastSingleTapAt = now;
          gestureName = 'Single Tap';
          targetAction = _singleTapAction;
        }
      } else if (code == 4) {
        gestureName = 'Long Press';
        targetAction = _longPressAction;
      } else if (code == 1) {
        gestureName = 'Decline Gesture';
        targetAction = _doubleTapAction;
      }
    }

    if (gestureName.isNotEmpty) {
      final entry = {
        'time': DateTime.now().toIso8601String(),
        'gesture': gestureName,
        'action': targetAction?.label ?? 'None',
      };
      setState(() {
        _gestureLog.insert(0, entry);
        if (_gestureLog.length > 30) _gestureLog.removeLast();
      });

      if (targetAction != null) {
        _executeAction(targetAction);
      }
    }
  }

  void _executeAction(GestureAction action) {
    switch (action) {
      case GestureAction.answerCall:
        _ble.answerPhoneCall();
        _showActionToast('Answering Incoming Call');
        break;
      case GestureAction.endCall:
        _ble.endOrDeclinePhoneCall();
        _showActionToast('Ending / Declining Call');
        break;
      case GestureAction.takePhoto:
        _ble.takePicture();
        _showActionToast('Capturing Remote Photo');
        break;
      case GestureAction.playPause:
        _ble.toggleMediaPlayPause();
        _showActionToast('Toggling Media Play/Pause');
        break;
      case GestureAction.prayerDnd:
        final alarmProvider = context.read<AlarmModeProvider>();
        requestPhoneMode(context, alarmProvider, PhoneMode.prayer);
        _showActionToast('Toggled Meditation DND');
        break;
      case GestureAction.none:
        break;
    }
  }

  void _showActionToast(String message) {
    if (!mounted) return;
    showGlassPill(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        leading: const GlassBackButton(),
        title: Text(
          'Gesture & Touch Controls',
          style: AppTypography.inter(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.gold))
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader('HARDWARE GESTURE SENSORS'),
                  const SizedBox(height: 10),

                  // Wrist-Flip Wake Gesture Card
                  _buildGlassCard([
                    SwitchListTile(
                      activeThumbColor: AppTheme.gold,
                      title: Text(
                        'Wrist-Flip Screen Wake',
                        style: AppTypography.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      subtitle: Text(
                        'Raise or flip your wrist to automatically illuminate the ring screen',
                        style: AppTypography.inter(color: AppTheme.textSec, fontSize: 12),
                      ),
                      value: _wristFlipEnabled,
                      onChanged: connected ? _setWristFlip : null,
                    ),
                    if (_wristFlipEnabled) ...[
                      const Divider(color: Colors.white12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            Text(
                              'Wearing Hand:',
                              style: AppTypography.inter(color: AppTheme.textSec, fontSize: 13),
                            ),
                            const Spacer(),
                            ChoiceChip(
                              label: const Text('Left Hand'),
                              selected: _isLeftHand,
                              selectedColor: AppTheme.gold,
                              labelStyle: TextStyle(color: _isLeftHand ? Colors.black : Colors.white),
                              onSelected: (_) => _setHandOrientation(true),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('Right Hand'),
                              selected: !_isLeftHand,
                              selectedColor: AppTheme.gold,
                              labelStyle: TextStyle(color: !_isLeftHand ? Colors.black : Colors.white),
                              onSelected: (_) => _setHandOrientation(false),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ]),

                  const SizedBox(height: 16),

                  // Touch Sensor Enable Card
                  _buildGlassCard([
                    SwitchListTile(
                      activeThumbColor: AppTheme.gold,
                      title: Text(
                        'Ring Touch Sensor',
                        style: AppTypography.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      subtitle: Text(
                        'Enable physical touch surface for tap, double-tap, and hold gestures',
                        style: AppTypography.inter(color: AppTheme.textSec, fontSize: 12),
                      ),
                      value: _touchSensorEnabled,
                      onChanged: connected ? _setTouchSensor : null,
                    ),
                  ]),

                  const SizedBox(height: 24),
                  _buildSectionHeader('GESTURE ACTION MAPPINGS'),
                  const SizedBox(height: 10),

                  _buildGlassCard([
                    _buildMappingTile(
                      title: 'Single Tap Gesture',
                      subtitle: 'Answer incoming call, take photo, or play media',
                      value: _singleTapAction,
                      onChanged: (act) {
                        if (act != null) {
                          setState(() => _singleTapAction = act);
                          _saveAction('gesture_single_tap', act);
                        }
                      },
                    ),
                    const Divider(color: Colors.white12),
                    _buildMappingTile(
                      title: 'Double Tap Gesture',
                      subtitle: 'Decline / end call or trigger assigned action',
                      value: _doubleTapAction,
                      onChanged: (act) {
                        if (act != null) {
                          setState(() => _doubleTapAction = act);
                          _saveAction('gesture_double_tap', act);
                        }
                      },
                    ),
                    const Divider(color: Colors.white12),
                    _buildMappingTile(
                      title: 'Long Press Gesture',
                      subtitle: 'Decline call, toggle Meditation DND, or execute action',
                      value: _longPressAction,
                      onChanged: (act) {
                        if (act != null) {
                          setState(() => _longPressAction = act);
                          _saveAction('gesture_long_press', act);
                        }
                      },
                    ),
                  ]),

                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: _buildSectionHeader('LIVE GESTURE STREAM & TESTER'),
                      ),
                      if (_gestureLog.isNotEmpty)
                        TextButton(
                          onPressed: () => setState(() => _gestureLog.clear()),
                          child: Text('Clear Log', style: AppTypography.inter(color: AppTheme.gold, fontSize: 12)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  _buildGlassCard([
                    if (_gestureLog.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Center(
                          child: Text(
                            'No gestures received yet.\nTap or press the ring sensor to test live mapping.',
                            textAlign: TextAlign.center,
                            style: AppTypography.inter(color: AppTheme.textSec, fontSize: 13),
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _gestureLog.length,
                        separatorBuilder: (_, _) => const Divider(color: Colors.white12, height: 1),
                        itemBuilder: (context, index) {
                          final item = _gestureLog[index];
                          return ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: AppTheme.goldTint,
                              child: Icon(Icons.touch_app_rounded, color: AppTheme.gold, size: 20),
                            ),
                            title: Text(
                              '${item['gesture']} ➔ ${item['action']}',
                              style: AppTypography.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              item['time'] ?? '',
                              style: AppTypography.inter(color: AppTheme.textSec, fontSize: 11),
                            ),
                          );
                        },
                      ),
                  ]),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String text) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.inter(
        color: AppTheme.textSec,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _buildGlassCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildMappingTile({
    required String title,
    required String subtitle,
    required GestureAction value,
    required ValueChanged<GestureAction?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: AppTypography.inter(color: AppTheme.textSec, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppTheme.card2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.gold.withValues(alpha: 0.3)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<GestureAction>(
                value: value,
                isExpanded: true,
                dropdownColor: AppTheme.card,
                icon: const Icon(Icons.arrow_drop_down_rounded, color: AppTheme.gold),
                items: GestureAction.values.map((action) {
                  return DropdownMenuItem<GestureAction>(
                    value: action,
                    child: Row(
                      children: [
                        Icon(action.icon, color: AppTheme.gold, size: 18),
                        const SizedBox(width: 10),
                        Text(
                          action.label,
                          style: AppTypography.inter(color: Colors.white, fontSize: 13),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
