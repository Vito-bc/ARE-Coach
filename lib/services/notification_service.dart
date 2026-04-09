import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static const _channelId = 'archi_ed_daily';
  static const _channelName = 'Daily Study Reminder';
  static const _notifId = 1;
  static const _hivePrefKey = 'dailyReminderEnabled';

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Call once at app startup (before any scheduling).
  static Future<void> init() async {
    if (_initialized) return;
    tz.initializeTimeZones();
    _initialized = true;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );
  }

  /// Returns the persisted preference (true = reminder on).
  static Future<bool> isEnabled() async {
    final box = await Hive.openBox('settings');
    return box.get(_hivePrefKey, defaultValue: false) as bool;
  }

  /// Request OS permission (iOS asks a dialog; Android 13+ does too).
  /// Returns true if granted.
  static Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    }

    final ios = _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final granted = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    return true; // other platforms — assume granted
  }

  /// Schedule a daily notification at [hour]:[minute] (local time).
  /// Cancels any existing reminder first.
  static Future<void> scheduleDailyReminder({
    int hour = 9,
    int minute = 0,
  }) async {
    await cancel();

    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      _notifId,
      'Time to study! 📐',
      'Keep your ARE prep streak going — a quick quiz takes 5 minutes.',
      scheduled,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Daily ARE study reminder',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          categoryIdentifier: 'daily_reminder',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    final box = await Hive.openBox('settings');
    await box.put(_hivePrefKey, true);
  }

  /// Cancel the daily reminder and persist the preference.
  static Future<void> cancel() async {
    await _plugin.cancel(_notifId);
    final box = await Hive.openBox('settings');
    await box.put(_hivePrefKey, false);
  }
}
