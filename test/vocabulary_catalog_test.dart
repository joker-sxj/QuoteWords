import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quotewords/features/words/data/isdc_catalog_parser.dart';
import 'package:quotewords/features/words/data/vocabulary_catalog.dart';

const cachedWord = VocabularyWord(
  id: 'cached',
  word: 'cached',
  phonetic: '/kæʃt/',
  translation: 'adj. 已缓存的',
  example: 'The data was cached.',
  frequency: 50,
);

const freshWord = VocabularyWord(
  id: 'fresh',
  word: 'fresh',
  phonetic: '/freʃ/',
  translation: 'adj. 新的',
  example: 'Fresh data is available.',
  frequency: 80,
);

class MemoryCatalogCache implements VocabularyCatalogCache {
  CatalogSnapshot? snapshot;

  @override
  Future<CatalogSnapshot?> read() async => snapshot;

  @override
  Future<void> write(CatalogSnapshot value) async => snapshot = value;
}

class RecordingCatalogSource implements VocabularyCatalogSource {
  RecordingCatalogSource(this.words, {this.error});

  final List<VocabularyWord> words;
  final Object? error;
  int calls = 0;

  @override
  Future<List<VocabularyWord>> fetch() async {
    calls++;
    if (error != null) throw error!;
    return words;
  }
}

class DeferredCatalogSource implements VocabularyCatalogSource {
  final completer = Completer<List<VocabularyWord>>();
  int calls = 0;

  @override
  Future<List<VocabularyWord>> fetch() {
    calls++;
    return completer.future;
  }
}

void main() {
  final now = DateTime.utc(2026, 8, 2, 9);

  test('uses a cache that is less than seven days old', () async {
    final cache = MemoryCatalogCache()
      ..snapshot = CatalogSnapshot(
        words: const [cachedWord],
        syncedAt: now.subtract(const Duration(days: 6)),
      );
    final source = RecordingCatalogSource(const [freshWord]);
    final catalog = CachedVocabularyCatalog(
      cache: cache,
      source: source,
      now: () => now,
    );

    final words = await catalog.load();

    expect(words, const [cachedWord]);
    expect(source.calls, 0);
  });

  test('returns stale data immediately and refreshes it in background', () async {
    final cache = MemoryCatalogCache()
      ..snapshot = CatalogSnapshot(
        words: const [cachedWord],
        syncedAt: now.subtract(const Duration(days: 8)),
      );
    final source = DeferredCatalogSource();
    final catalog = CachedVocabularyCatalog(
      cache: cache,
      source: source,
      now: () => now,
    );

    var returnedBeforeNetwork = false;
    final load = catalog.load()..then((_) => returnedBeforeNetwork = true);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final wasImmediate = returnedBeforeNetwork;
    source.completer.complete(const [freshWord]);
    final words = await load;
    await Future<void>.delayed(Duration.zero);

    expect(wasImmediate, isTrue);
    expect(words, const [cachedWord]);
    expect(source.calls, 1);
    expect(cache.snapshot?.words, const [freshWord]);
    expect(cache.snapshot?.syncedAt, now);
  });

  test('keeps stale words when the third-party page is unavailable', () async {
    final cache = MemoryCatalogCache()
      ..snapshot = CatalogSnapshot(
        words: const [cachedWord],
        syncedAt: now.subtract(const Duration(days: 8)),
      );
    final source = RecordingCatalogSource(
      const [],
      error: StateError('offline'),
    );
    final catalog = CachedVocabularyCatalog(
      cache: cache,
      source: source,
      now: () => now,
    );

    final words = await catalog.load();

    expect(words, const [cachedWord]);
    expect(source.calls, 1);
  });
}
