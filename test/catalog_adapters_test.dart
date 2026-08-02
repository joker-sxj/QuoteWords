import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quoteimage_mobile/features/words/data/catalog_adapters.dart';
import 'package:quoteimage_mobile/features/words/data/isdc_catalog_parser.dart';
import 'package:quoteimage_mobile/features/words/data/vocabulary_catalog.dart';

void main() {
  test('JSON file cache round-trips only the minimal catalog', () async {
    final directory = await Directory.systemTemp.createTemp('quote-catalog-');
    addTearDown(() => directory.delete(recursive: true));
    final cache = JsonFileVocabularyCatalogCache(
      directoryProvider: () async => directory,
    );
    final snapshot = CatalogSnapshot(
      words: const [
        VocabularyWord(
          id: 'allocate',
          word: 'allocate',
          phonetic: '/ˈæləkeɪt/',
          translation: 'v. 分配；划拨',
          example: 'Allocate funds carefully.',
          frequency: 68,
        ),
      ],
      syncedAt: DateTime.utc(2026, 8, 2, 9),
    );

    await cache.write(snapshot);
    final loaded = await cache.read();

    expect(loaded?.syncedAt, snapshot.syncedAt);
    expect(loaded?.words.single.toJson(), snapshot.words.single.toJson());
    final persisted = await File(
      '${directory.path}/ielts-catalog.json',
    ).readAsString();
    expect(persisted, isNot(contains('audio')));
    expect(persisted, isNot(contains('trueExamples')));
  });

  test(
    'ISDC source downloads and parses words at frequency 40 or higher',
    () async {
      final payload = jsonEncode({
        'g': [
          {
            'ws': [
              {
                'w': 'allocate',
                'p': 'ˈæləkeɪt',
                't': 'v. 分配；划拨',
                'e': 'Allocate funds carefully.',
                'oc': 40,
              },
              {'w': 'rare', 't': 'adj. 少见的', 'oc': 39},
            ],
          },
        ],
      });
      final bytes = [...utf8.encode(payload)];
      while (bytes.length % 4 != 0) {
        bytes.add(0x20);
      }
      final page = '<script id="asp-data">${_base85(bytes)}</script>';
      var requests = 0;
      final source = IsdcVocabularyCatalogSource(
        loadPage: () async {
          requests++;
          return page;
        },
        decodeSegment: (data) async => Uint8List.fromList(data),
      );

      final words = await source.fetch();

      expect(requests, 1);
      expect(words.map((word) => word.id), ['allocate']);
    },
  );
}

String _base85(List<int> bytes) {
  final alphabet = String.fromCharCodes(
    [
      for (var code = 33; code <= 126; code++)
        if (code != 34 && code != 39 && code != 60) code,
    ].take(85),
  );
  final output = StringBuffer();
  for (var offset = 0; offset < bytes.length; offset += 4) {
    var value =
        bytes[offset] * 0x1000000 +
        bytes[offset + 1] * 0x10000 +
        bytes[offset + 2] * 0x100 +
        bytes[offset + 3];
    final digits = List<int>.filled(5, 0);
    for (var index = 4; index >= 0; index--) {
      digits[index] = value % 85;
      value ~/= 85;
    }
    for (final digit in digits) {
      output.write(alphabet[digit]);
    }
  }
  return output.toString();
}
