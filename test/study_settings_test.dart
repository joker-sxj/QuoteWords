import 'package:flutter_test/flutter_test.dart';
import 'package:quotewords/features/words/domain/study_settings.dart';

void main() {
  test('defaults match the six-month Android study plan', () {
    const settings = StudySettings();

    expect(settings.newWordsPerDay, 8);
    expect(settings.dailyLimit, 24);
    expect(settings.reminderHour, 9);
    expect(settings.reminderMinute, 0);
    expect(settings.estimatedDaysFor(1397), 175);
  });

  test('normalization keeps adjustable quotas within the 24-card cap', () {
    final settings = const StudySettings().copyWith(
      newWordsPerDay: 30,
      dailyLimit: 60,
      reminderHour: 27,
      reminderMinute: -4,
    );

    expect(settings.newWordsPerDay, 24);
    expect(settings.dailyLimit, 24);
    expect(settings.reminderHour, 23);
    expect(settings.reminderMinute, 0);
  });
}
