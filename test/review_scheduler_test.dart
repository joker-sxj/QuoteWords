import 'package:flutter_test/flutter_test.dart';
import 'package:quotewords/features/words/domain/review_scheduler.dart';
import 'package:quotewords/features/words/domain/study_settings.dart';

void main() {
  final now = DateTime(2026, 8, 2, 9);

  test('good recall follows the Ebbinghaus learning intervals', () {
    const scheduler = ReviewScheduler();
    var progress = WordProgress.initial(
      'deposit',
      dueAt: DateTime(2026, 8, 2, 9),
    );

    final expected = <Duration>[
      const Duration(minutes: 10),
      const Duration(days: 1),
      const Duration(days: 3),
      const Duration(days: 7),
      const Duration(days: 14),
      const Duration(days: 30),
    ];

    for (final interval in expected) {
      final rated = scheduler.rate(progress, RecallRating.good, now);
      expect(rated.dueAt, now.add(interval));
      progress = rated.copyWith(dueAt: now);
    }
  });

  test('forgotten resets and easy advances an extra stage', () {
    const scheduler = ReviewScheduler();
    final mature = WordProgress(
      wordId: 'deposit',
      step: 4,
      dueAt: now,
      lapses: 0,
    );

    final forgotten = scheduler.rate(mature, RecallRating.forgotten, now);
    expect(forgotten.step, 1);
    expect(forgotten.lapses, 1);
    expect(forgotten.dueAt, now.add(const Duration(minutes: 10)));

    final easy = scheduler.rate(
      WordProgress.initial('deposit', dueAt: now),
      RecallRating.easy,
      now,
    );
    expect(easy.step, 2);
    expect(easy.dueAt, now.add(const Duration(days: 1)));
  });

  test('daily plan puts due reviews first and pauses new words at the cap', () {
    final reviews = List.generate(
      24,
      (index) => StudyCandidate.review(
        wordId: 'review-$index',
        dueAt: now.subtract(Duration(minutes: index)),
      ),
    );
    final newWords = List.generate(
      8,
      (index) =>
          StudyCandidate.newWord(wordId: 'new-$index', frequency: 100 - index),
    );

    final plan = DailyStudyPlan.build(
      dueReviews: reviews,
      newWords: newWords,
      settings: const StudySettings(),
    );

    expect(plan.items, hasLength(24));
    expect(plan.items.every((item) => !item.isNew), isTrue);
    expect(plan.newWordCount, 0);
    expect(plan.reviewCount, 24);
  });

  test(
    'daily plan fills remaining capacity with the highest-frequency words',
    () {
      final plan = DailyStudyPlan.build(
        dueReviews: [StudyCandidate.review(wordId: 'due', dueAt: now)],
        newWords: [
          const StudyCandidate.newWord(wordId: 'lower', frequency: 41),
          const StudyCandidate.newWord(wordId: 'higher', frequency: 99),
        ],
        settings: const StudySettings(newWordsPerDay: 1, dailyLimit: 3),
      );

      expect(plan.items.map((item) => item.wordId), ['due', 'higher']);
      expect(plan.newWordCount, 1);
      expect(plan.reviewCount, 1);
    },
  );
}
