import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quotewords/features/words/data/study_session.dart';
import 'package:quotewords/features/words/data/study_state_store.dart';
import 'package:quotewords/features/words/domain/review_scheduler.dart';

void main() {
  test(
    'JSON file store restores the daily queue and review progress',
    () async {
      final directory = await Directory.systemTemp.createTemp('quote-study-');
      addTearDown(() => directory.delete(recursive: true));
      final store = JsonFileStudyStateStore(
        directoryProvider: () async => directory,
      );
      final dueAt = DateTime.utc(2026, 8, 3, 9, 10);
      final state = StudyState(
        progress: {
          'allocate': WordProgress(
            wordId: 'allocate',
            step: 2,
            dueAt: dueAt,
            lapses: 1,
          ),
        },
        sessionDate: '2026-08-02',
        sessionWordIds: const ['allocate', 'deposit'],
        currentIndex: 1,
      );

      await store.save(state);
      final loaded = await store.load();

      expect(loaded.sessionDate, state.sessionDate);
      expect(loaded.sessionWordIds, state.sessionWordIds);
      expect(loaded.currentIndex, state.currentIndex);
      expect(loaded.progress['allocate']?.wordId, 'allocate');
      expect(loaded.progress['allocate']?.step, 2);
      expect(loaded.progress['allocate']?.dueAt, dueAt);
      expect(loaded.progress['allocate']?.lapses, 1);
    },
  );

  test('missing or corrupt study state falls back to an empty state', () async {
    final directory = await Directory.systemTemp.createTemp('quote-study-');
    addTearDown(() => directory.delete(recursive: true));
    final store = JsonFileStudyStateStore(
      directoryProvider: () async => directory,
    );

    expect((await store.load()).sessionWordIds, isEmpty);

    await File('${directory.path}/ielts-study-state.json').writeAsString('{');
    final loaded = await store.load();

    expect(loaded.progress, isEmpty);
    expect(loaded.sessionDate, isNull);
    expect(loaded.currentIndex, 0);
  });
}
