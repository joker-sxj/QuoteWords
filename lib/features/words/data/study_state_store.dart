import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/review_scheduler.dart';
import 'study_session.dart';

typedef StudyDirectoryProvider = Future<Directory> Function();

class JsonFileStudyStateStore implements StudyStateStore {
  JsonFileStudyStateStore({StudyDirectoryProvider? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static const fileName = 'ielts-study-state.json';
  final StudyDirectoryProvider _directoryProvider;

  @override
  Future<StudyState> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const StudyState();
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return const StudyState();

      final rawProgress = json['progress'];
      if (rawProgress is! Map<String, dynamic>) return const StudyState();
      return StudyState(
        progress: Map.unmodifiable(
          rawProgress.map((wordId, value) {
            final item = value as Map<String, dynamic>;
            return MapEntry(
              wordId,
              WordProgress(
                wordId: wordId,
                step: item['step']! as int,
                dueAt: DateTime.parse(item['dueAt']! as String).toUtc(),
                lapses: item['lapses']! as int,
              ),
            );
          }),
        ),
        sessionDate: json['sessionDate'] as String?,
        sessionWordIds: List.unmodifiable(
          (json['sessionWordIds']! as List).whereType<String>(),
        ),
        currentIndex: json['currentIndex']! as int,
      );
    } on FileSystemException {
      return const StudyState();
    } on FormatException {
      return const StudyState();
    } on TypeError {
      return const StudyState();
    }
  }

  @override
  Future<void> save(StudyState state) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'progress': {
          for (final entry in state.progress.entries)
            entry.key: {
              'step': entry.value.step,
              'dueAt': entry.value.dueAt.toUtc().toIso8601String(),
              'lapses': entry.value.lapses,
            },
        },
        'sessionDate': state.sessionDate,
        'sessionWordIds': state.sessionWordIds,
        'currentIndex': state.currentIndex,
      }),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<File> _file() async {
    final directory = await _directoryProvider();
    return File('${directory.path}/$fileName');
  }
}
