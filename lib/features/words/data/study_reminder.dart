import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../domain/study_settings.dart';

abstract interface class StudyReminder {
  Future<void> schedule(StudySettings settings);
}

class LocalStudyReminder implements StudyReminder {
  LocalStudyReminder({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _notificationId = 900;
  static const _channelId = 'daily_word_study';
  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  @override
  Future<void> schedule(StudySettings settings) async {
    if (!Platform.isAndroid) return;
    await _initialize();
    await _plugin.cancel(id: _notificationId);
    await _plugin.zonedSchedule(
      id: _notificationId,
      title: '今日雅思词卡',
      body: '${settings.newWordsPerDay} 个新词，先完成到期复习',
      scheduledDate: nextReminderTime(settings, tz.TZDateTime.now(tz.local)),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          '每日词卡',
          channelDescription: '每天提醒开始雅思词卡学习',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'word-study',
    );
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    tz.initializeTimeZones();
    final timezone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezone.identifier));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    _initialized = true;
  }
}

tz.TZDateTime nextReminderTime(StudySettings settings, tz.TZDateTime now) {
  var scheduled = tz.TZDateTime(
    now.location,
    now.year,
    now.month,
    now.day,
    settings.reminderHour,
    settings.reminderMinute,
  );
  if (!scheduled.isAfter(now)) {
    scheduled = scheduled.add(const Duration(days: 1));
  }
  return scheduled;
}
