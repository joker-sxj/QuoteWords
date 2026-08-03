import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quotewords/features/words/data/isdc_catalog_parser.dart';

void main() {
  test('keeps only high-frequency fields needed by the e-paper card', () async {
    final source = jsonEncode({
      'g': [
        {
          'n': '出现40~99次',
          'ws': [
            {
              'w': 'Allocate',
              'p': 'ˈæləkeɪt',
              't': 'v. 分配；划拨',
              'e': 'The council allocated funds to housing.',
              'ec': '市政会把资金划拨给住房项目。',
              'oc': 68,
              'ed': 'an intentionally excluded long definition',
              'ay': 'audio/example.mp3',
              'dt': {'allocate': []},
            },
            {
              'w': 'rare',
              'p': 'reə',
              't': 'adj. 少见的',
              'e': 'It is rare.',
              'oc': 2,
            },
          ],
        },
      ],
    });
    final padded = [...utf8.encode(source)];
    while (padded.length % 4 != 0) {
      padded.add(0x20);
    }
    final html =
        '''
      <html><body>
        <script type="application/json" id="asp-data">${_base85(padded)}</script>
      </body></html>
    ''';
    final parser = IsdcCatalogParser(
      decodeSegment: (bytes) async => Uint8List.fromList(bytes),
    );

    final words = await parser.parse(html, minimumFrequency: 40);

    expect(words, hasLength(1));
    expect(words.single.id, 'allocate');
    expect(words.single.word, 'Allocate');
    expect(words.single.phonetic, '/ˈæləkeɪt/');
    expect(words.single.translation, 'v. 分配；划拨');
    expect(words.single.example, 'The council allocated funds to housing.');
    expect(words.single.exampleTranslation, '市政会把资金划拨给住房项目。');
    expect(words.single.frequency, 68);
    expect(words.single.toJson().keys, {
      'id',
      'word',
      'phonetic',
      'translation',
      'example',
      'exampleTranslation',
      'frequency',
    });
  });

  test('rejects pages without the structured dictionary payload', () async {
    final parser = IsdcCatalogParser(
      decodeSegment: (bytes) async => Uint8List.fromList(bytes),
    );

    expect(
      () => parser.parse('<html></html>', minimumFrequency: 40),
      throwsA(isA<FormatException>()),
    );
  });
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
