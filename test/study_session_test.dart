import 'package:flutter_test/flutter_test.dart';
import 'package:quoteimage_mobile/features/words/data/isdc_catalog_parser.dart';
import 'package:quoteimage_mobile/features/words/data/study_session.dart';
import 'package:quoteimage_mobile/features/words/domain/review_scheduler.dart';
import 'package:quoteimage_mobile/features/words/domain/study_settings.dart';

const reviewWord = VocabularyWord(
  id: 'review',
  word: 'review',
  phonetic: '/rɪˈvjuː/',
  translation: 'v. 复习',
  example: 'Review the material regularly.',
  frequency: 90,
);

const highWord = VocabularyWord(
  id: 'high',
  word: 'high',
  phonetic: '/haɪ/',
  translation: 'adj. 高的',
  example: 'The score was high.',
  frequency: 80,
);

const lowerWord = VocabularyWord(
  id: 'lower',
  word: 'lower',
  phonetic: '/ˈləʊə/',
  translation: 'adj. 较低的',
  example: 'The lower figure is correct.',
  frequency: 50,
);

class MemoryStudyStateStore implements StudyStateStore {
  StudyState value = const StudyState();

  @override
  Future<StudyState> load() async => value;

  @override
  Future<void> save(StudyState state) async => value = state;
}

void main() {
  final now = DateTime.utc(2026, 8, 2, 9);

  test('builds a fixed daily queue with due reviews before new words', () async {
    final store = MemoryStudyStateStore()
      ..value = StudyState(
        progress: {
          'review': WordProgress(
            wordId: 'review',
            step: 3,
            dueAt: now.subtract(const Duration(minutes: 1)),
            lapses: 0,
          ),
        },
      );
    final session = StudySession(
      words: const [lowerWord, highWord, reviewWord],
      store: store,
      settings: const StudySettings(newWordsPerDay: 1, dailyLimit: 2),
      now: () => now,
    );

    await session.load();

    expect(session.queue.map((word) => word.id), ['review', 'high']);
    expect(session.current?.id, 'review');
    expect(store.value.sessionDate, '2026-08-02');
    expect(store.value.sessionWordIds, ['review', 'high']);
  });

  test('rating persists the interval and resumes at the next word', () async {
    final store = MemoryStudyStateStore();
    final session = StudySession(
      words: const [highWord, lowerWord],
      store: store,
      settings: const StudySettings(newWordsPerDay: 2, dailyLimit: 2),
      now: () => now,
    );
    await session.load();

    await session.rate(RecallRating.good);

    expect(store.value.progress['high']?.step, 1);
    expect(
      store.value.progress['high']?.dueAt,
      now.add(const Duration(minutes: 10)),
    );
    expect(session.current?.id, 'lower');

    final reopened = StudySession(
      words: const [highWord, lowerWord],
      store: store,
      settings: const StudySettings(newWordsPerDay: 2, dailyLimit: 2),
      now: () => now.add(const Duration(minutes: 2)),
    );
    await reopened.load();

    expect(reopened.current?.id, 'lower');
    expect(reopened.queue.map((word) => word.id), ['high', 'lower']);
  });

  test('a new day rebuilds the queue from due progress', () async {
    final store = MemoryStudyStateStore()
      ..value = StudyState(
        progress: {
          'review': WordProgress(
            wordId: 'review',
            step: 1,
            dueAt: now,
            lapses: 0,
          ),
        },
        sessionDate: '2026-08-01',
        sessionWordIds: const ['high'],
        currentIndex: 1,
      );
    final session = StudySession(
      words: const [highWord, reviewWord],
      store: store,
      settings: const StudySettings(newWordsPerDay: 1, dailyLimit: 2),
      now: () => now,
    );

    await session.load();

    expect(session.current?.id, 'review');
    expect(store.value.sessionDate, '2026-08-02');
  });
}
