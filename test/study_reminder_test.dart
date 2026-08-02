import 'package:flutter_test/flutter_test.dart';
import 'package:quoteimage_mobile/features/words/data/study_reminder.dart';
import 'package:quoteimage_mobile/features/words/domain/study_settings.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(tz.initializeTimeZones);

  test('schedules 09:00 later on the same day', () {
    final location = tz.getLocation('Asia/Shanghai');
    final now = tz.TZDateTime(location, 2026, 8, 2, 8, 30);

    final scheduled = nextReminderTime(const StudySettings(), now);

    expect(scheduled, tz.TZDateTime(location, 2026, 8, 2, 9));
  });

  test('moves an elapsed reminder to the following day', () {
    final location = tz.getLocation('Asia/Shanghai');
    final now = tz.TZDateTime(location, 2026, 8, 2, 9, 1);

    final scheduled = nextReminderTime(const StudySettings(), now);

    expect(scheduled, tz.TZDateTime(location, 2026, 8, 3, 9));
  });
}
