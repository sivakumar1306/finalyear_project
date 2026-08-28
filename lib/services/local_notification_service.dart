import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/material.dart';

class LocalNotificationService {
  static final LocalNotificationService _instance =
      LocalNotificationService._internal();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // For iOS, setup permissions appropriately if needed
    final DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    final InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );

    await flutterLocalNotificationsPlugin.initialize(settings: initializationSettings);

    _initialized = true;
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    if (!_initialized) await init();

    if (scheduledDate.isBefore(DateTime.now())) {
      debugPrint(
        '[LocalNotificationService] Attempted to schedule notification in the past: $scheduledDate',
      );
      return;
    }

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(scheduledDate, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'womens_health_channel',
          'Women\'s Health Reminders',
          channelDescription: 'Reminders for period and fertility tracking',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
    debugPrint(
      '[LocalNotificationService] Scheduled notification id $id for $scheduledDate',
    );
  }

  Future<void> cancelNotification(int id) async {
    if (!_initialized) await init();
    await flutterLocalNotificationsPlugin.cancel(id: id);
    debugPrint('[LocalNotificationService] Cancelled notification id $id');
  }

  Future<void> cancelAllNotifications() async {
    if (!_initialized) await init();
    await flutterLocalNotificationsPlugin.cancelAll();
  }

  /// Syncs women's health notifications based on user preferences and predictions
  Future<void> syncWomensHealthNotifications({
    required DateTime? nextPeriodDate,
    required DateTime? fertileWindowStartDate,
    required bool periodRemindersEnabled,
    required bool fertileRemindersEnabled,
    String scheduleOffset = '1 day before',
    String timeOfDay = '12:00 pm',
  }) async {
    const int periodNotificationId = 1001;
    const int fertileNotificationId = 1002;

    // Parse timeOfDay (e.g. "12:00 pm")
    int hour = 12;
    int minute = 0;
    try {
      final parts = timeOfDay.split(' ');
      if (parts.length == 2) {
        final timeParts = parts[0].split(':');
        if (timeParts.length == 2) {
          hour = int.parse(timeParts[0]);
          minute = int.parse(timeParts[1]);
          if (parts[1].toLowerCase() == 'pm' && hour != 12) {
            hour += 12;
          } else if (parts[1].toLowerCase() == 'am' && hour == 12) {
            hour = 0;
          }
        }
      }
    } catch (e) {
      debugPrint('[LocalNotificationService] Error parsing time: $e');
    }

    // Parse scheduleOffset (e.g. "1 day before")
    int daysOffset = 1;
    if (scheduleOffset.contains('day')) {
      final match = RegExp(r'(\d+)').firstMatch(scheduleOffset);
      if (match != null) {
        daysOffset = int.parse(match.group(1)!);
      }
    }

    if (periodRemindersEnabled && nextPeriodDate != null) {
      final scheduledDate = DateTime(
        nextPeriodDate.year,
        nextPeriodDate.month,
        nextPeriodDate.day,
        hour,
        minute,
      ).subtract(Duration(days: daysOffset));

      await scheduleNotification(
        id: periodNotificationId,
        title: 'Period Reminder',
        body:
            'Your next period is expected to start tomorrow.', // Simplified for now
        scheduledDate: scheduledDate,
      );
    } else {
      await cancelNotification(periodNotificationId);
    }

    if (fertileRemindersEnabled && fertileWindowStartDate != null) {
      final scheduledDate = DateTime(
        fertileWindowStartDate.year,
        fertileWindowStartDate.month,
        fertileWindowStartDate.day,
        hour,
        minute,
      ).subtract(Duration(days: daysOffset));

      await scheduleNotification(
        id: fertileNotificationId,
        title: 'Fertility Window',
        body: 'Your fertile window is expected to begin tomorrow.',
        scheduledDate: scheduledDate,
      );
    } else {
      await cancelNotification(fertileNotificationId);
    }
  }
}
