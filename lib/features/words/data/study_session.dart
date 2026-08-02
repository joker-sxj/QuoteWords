import 'isdc_catalog_parser.dart';
import '../domain/review_scheduler.dart';
import '../domain/study_settings.dart';

class StudyState {
  const StudyState({
    this.progress = const {},
    this.sessionDate,
    this.sessionWordIds = const [],
    this.currentIndex = 0,
  });

  final Map<String, WordProgress> progress;
  final String? sessionDate;
  final List<String> sessionWordIds;
  final int currentIndex;

  StudyState copyWith({
    Map<String, WordProgress>? progress,
    String? sessionDate,
    List<String>? sessionWordIds,
    int? currentIndex,
  }) {
    return StudyState(
      progress: progress ?? this.progress,
      sessionDate: sessionDate ?? this.sessionDate,
      sessionWordIds: sessionWordIds ?? this.sessionWordIds,
      currentIndex: currentIndex ?? this.currentIndex,
    );
  }
}

abstract interface class StudyStateStore {
  Future<StudyState> load();
  Future<void> save(StudyState state);
}

class StudySession {
  StudySession({
    required List<VocabularyWord> words,
    required StudyStateStore store,
    required StudySettings settings,
    DateTime Function()? now,
    ReviewScheduler scheduler = const ReviewScheduler(),
  }) : _words = List.unmodifiable(words),
       _store = store,
       _settings = settings,
       _now = now ?? DateTime.now,
       _scheduler = scheduler;

  final List<VocabularyWord> _words;
  final StudyStateStore _store;
  final StudySettings _settings;
  final DateTime Function() _now;
  final ReviewScheduler _scheduler;

  StudyState _state = const StudyState();
  List<VocabularyWord> _queue = const [];

  List<VocabularyWord> get queue => _queue;

  VocabularyWord? get current {
    if (_state.currentIndex >= _queue.length) return null;
    return _queue[_state.currentIndex];
  }

  Future<void> load() async {
    final saved = await _store.load();
    final currentTime = _now();
    final today = _dateKey(currentTime);
    final wordsById = {for (final word in _words) word.id: word};

    if (saved.sessionDate == today) {
      _queue = List.unmodifiable(
        saved.sessionWordIds.map((id) => wordsById[id]).nonNulls,
      );
      _state = saved.copyWith(
        currentIndex: saved.currentIndex.clamp(0, _queue.length),
      );
      return;
    }

    final plan = DailyStudyPlan.build(
      dueReviews: [
        for (final entry in saved.progress.entries)
          if (wordsById.containsKey(entry.key) &&
              !entry.value.dueAt.isAfter(currentTime))
            StudyCandidate.review(wordId: entry.key, dueAt: entry.value.dueAt),
      ],
      newWords: [
        for (final word in _words)
          if (!saved.progress.containsKey(word.id))
            StudyCandidate.newWord(wordId: word.id, frequency: word.frequency),
      ],
      settings: _settings,
    );
    _queue = List.unmodifiable(
      plan.items.map((item) => wordsById[item.wordId]).nonNulls,
    );
    _state = StudyState(
      progress: saved.progress,
      sessionDate: today,
      sessionWordIds: _queue.map((word) => word.id).toList(growable: false),
    );
    await _store.save(_state);
  }

  Future<void> rate(RecallRating rating) async {
    final word = current;
    if (word == null) return;

    final currentTime = _now();
    final existing =
        _state.progress[word.id] ??
        WordProgress.initial(word.id, dueAt: currentTime);
    final progress = Map<String, WordProgress>.of(_state.progress)
      ..[word.id] = _scheduler.rate(existing, rating, currentTime);
    _state = _state.copyWith(
      progress: Map.unmodifiable(progress),
      currentIndex: _state.currentIndex + 1,
    );
    await _store.save(_state);
  }
}

String _dateKey(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
