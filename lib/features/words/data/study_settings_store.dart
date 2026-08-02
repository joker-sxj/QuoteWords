import 'package:shared_preferences/shared_preferences.dart';

import '../domain/study_settings.dart';

abstract interface class StudySettingsStore {
  Future<StudySettings> load();
  Future<void> save(StudySettings settings);
}

class PersistentStudySettingsStore implements StudySettingsStore {
  static const _newWordsKey = 'words.new_per_day';
  static const _dailyLimitKey = 'words.daily_limit';
  static const _reminderHourKey = 'words.reminder_hour';
  static const _reminderMinuteKey = 'words.reminder_minute';

  @override
  Future<StudySettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    return const StudySettings().copyWith(
      newWordsPerDay: preferences.getInt(_newWordsKey),
      dailyLimit: preferences.getInt(_dailyLimitKey),
      reminderHour: preferences.getInt(_reminderHourKey),
      reminderMinute: preferences.getInt(_reminderMinuteKey),
    );
  }

  @override
  Future<void> save(StudySettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setInt(_newWordsKey, settings.newWordsPerDay),
      preferences.setInt(_dailyLimitKey, settings.dailyLimit),
      preferences.setInt(_reminderHourKey, settings.reminderHour),
      preferences.setInt(_reminderMinuteKey, settings.reminderMinute),
    ]);
  }
}
