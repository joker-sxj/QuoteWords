import 'study_settings.dart';

enum RecallRating { forgotten, hard, good, easy }

class WordProgress {
  const WordProgress({
    required this.wordId,
    required this.step,
    required this.dueAt,
    required this.lapses,
  });

  factory WordProgress.initial(String wordId, {required DateTime dueAt}) {
    return WordProgress(wordId: wordId, step: 0, dueAt: dueAt, lapses: 0);
  }

  final String wordId;
  final int step;
  final DateTime dueAt;
  final int lapses;

  WordProgress copyWith({int? step, DateTime? dueAt, int? lapses}) {
    return WordProgress(
      wordId: wordId,
      step: step ?? this.step,
      dueAt: dueAt ?? this.dueAt,
      lapses: lapses ?? this.lapses,
    );
  }
}

class ReviewScheduler {
  const ReviewScheduler();

  static const intervals = <Duration>[
    Duration(minutes: 10),
    Duration(days: 1),
    Duration(days: 3),
    Duration(days: 7),
    Duration(days: 14),
    Duration(days: 30),
  ];

  WordProgress rate(WordProgress progress, RecallRating rating, DateTime now) {
    if (rating == RecallRating.forgotten) {
      return progress.copyWith(
        step: 1,
        dueAt: now.add(intervals.first),
        lapses: progress.lapses + 1,
      );
    }

    final advance = rating == RecallRating.easy ? 2 : 1;
    final nextStep = (progress.step + advance).clamp(1, intervals.length);
    var interval = intervals[nextStep - 1];
    if (rating == RecallRating.hard) {
      interval = Duration(milliseconds: (interval.inMilliseconds / 2).round());
      if (interval < intervals.first) interval = intervals.first;
    }
    return progress.copyWith(step: nextStep, dueAt: now.add(interval));
  }
}

class StudyCandidate {
  const StudyCandidate.newWord({required this.wordId, required this.frequency})
    : isNew = true,
      dueAt = null;

  const StudyCandidate.review({required this.wordId, required this.dueAt})
    : isNew = false,
      frequency = 0;

  final String wordId;
  final bool isNew;
  final int frequency;
  final DateTime? dueAt;
}

class DailyStudyPlan {
  const DailyStudyPlan(this.items);

  factory DailyStudyPlan.build({
    required List<StudyCandidate> dueReviews,
    required List<StudyCandidate> newWords,
    required StudySettings settings,
  }) {
    final reviews = [...dueReviews]
      ..sort((left, right) => left.dueAt!.compareTo(right.dueAt!));
    final fresh = [...newWords]
      ..sort((left, right) => right.frequency.compareTo(left.frequency));

    final items = reviews.take(settings.dailyLimit).toList();
    final remaining = settings.dailyLimit - items.length;
    if (remaining > 0) {
      items.addAll(fresh.take(settings.newWordsPerDay.clamp(0, remaining)));
    }
    return DailyStudyPlan(List.unmodifiable(items));
  }

  final List<StudyCandidate> items;

  int get newWordCount => items.where((item) => item.isNew).length;
  int get reviewCount => items.length - newWordCount;
}
