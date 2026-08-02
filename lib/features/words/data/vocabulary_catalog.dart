import 'isdc_catalog_parser.dart';

class CatalogSnapshot {
  const CatalogSnapshot({required this.words, required this.syncedAt});

  final List<VocabularyWord> words;
  final DateTime syncedAt;
}

abstract interface class VocabularyCatalogCache {
  Future<CatalogSnapshot?> read();
  Future<void> write(CatalogSnapshot value);
}

abstract interface class VocabularyCatalogSource {
  Future<List<VocabularyWord>> fetch();
}

abstract interface class VocabularyCatalog {
  Future<List<VocabularyWord>> load();
}

class CachedVocabularyCatalog implements VocabularyCatalog {
  CachedVocabularyCatalog({
    required VocabularyCatalogCache cache,
    required VocabularyCatalogSource source,
    DateTime Function()? now,
    this.maxAge = const Duration(days: 7),
  }) : _cache = cache,
       _source = source,
       _now = now ?? DateTime.now;

  final VocabularyCatalogCache _cache;
  final VocabularyCatalogSource _source;
  final DateTime Function() _now;
  final Duration maxAge;

  @override
  Future<List<VocabularyWord>> load() async {
    final cached = await _cache.read();
    final currentTime = _now();
    if (cached != null &&
        cached.words.isNotEmpty &&
        currentTime.difference(cached.syncedAt) < maxAge) {
      return cached.words;
    }

    try {
      final words = await _source.fetch();
      if (words.isEmpty) throw const FormatException('同步结果没有高频词');
      final snapshot = CatalogSnapshot(words: words, syncedAt: currentTime);
      await _cache.write(snapshot);
      return words;
    } catch (_) {
      if (cached != null && cached.words.isNotEmpty) return cached.words;
      rethrow;
    }
  }
}
