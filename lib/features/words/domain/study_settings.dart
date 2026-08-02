import 'dart:math' as math;

class StudySettings {
  const StudySettings({
    this.newWordsPerDay = 8,
    this.dailyLimit = 24,
    this.reminderHour = 9,
    this.reminderMinute = 0,
  });

  final int newWordsPerDay;
  final int dailyLimit;
  final int reminderHour;
  final int reminderMinute;

  StudySettings copyWith({
    int? newWordsPerDay,
    int? dailyLimit,
    int? reminderHour,
    int? reminderMinute,
  }) {
    final normalizedNewWords = (newWordsPerDay ?? this.newWordsPerDay).clamp(
      1,
      40,
    );
    final requestedLimit = (dailyLimit ?? this.dailyLimit).clamp(1, 60);
    return StudySettings(
      newWordsPerDay: normalizedNewWords,
      dailyLimit: math.max(normalizedNewWords, requestedLimit),
      reminderHour: (reminderHour ?? this.reminderHour).clamp(0, 23),
      reminderMinute: (reminderMinute ?? this.reminderMinute).clamp(0, 59),
    );
  }

  int estimatedDaysFor(int wordCount) {
    if (wordCount <= 0) return 0;
    return (wordCount / newWordsPerDay).ceil();
  }
}
