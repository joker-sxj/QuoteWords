import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:quotewords/core/ble/quote_protocol.dart';
import 'package:quotewords/features/words/domain/word_card.dart';
import 'package:quotewords/features/words/rendering/word_card_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renders a crisp Quote/0 frame at the physical card size', () async {
    const content = WordCardContent(
      word: 'deposit',
      phonetic: '/dɪˈpɒzɪt/',
      translation: 'n. 押金；存款',
      example: 'Pay a deposit to reserve it.',
      frequency: 102,
      reviewLabel: '新词',
      position: 1,
      total: 8,
    );

    final rendered = await renderWordCard(content);
    final preview = image.decodePng(rendered.previewPng)!;

    expect((preview.width, preview.height), (296, 152));
    expect(rendered.frame, hasLength(QuoteProtocol.frameSize));
    expect(rendered.frame.toSet().length, greaterThan(1));
  });

  test('long words fit without truncation or overflow', () {
    const content = WordCardContent(
      word: 'electroencephalographically',
      phonetic: '/ɪˌlektrəʊensefələˈɡræfɪkli/',
      translation: 'adv. 通过脑电图检查',
      example: 'The response was recorded electroencephalographically.',
      frequency: 40,
      reviewLabel: '复习 D+3',
      position: 24,
      total: 24,
    );

    final layout = WordCardLayout.resolve(content);

    expect(layout.wordFontSize, greaterThanOrEqualTo(14));
    expect(layout.measuredWordWidth, lessThanOrEqualTo(layout.wordMaxWidth));
    expect(layout.wordIsTruncated, isFalse);
  });

  test('phonetic and Chinese definition share one rendered row', () async {
    final blank = await renderWordCard(_compactContent());
    final phonetic = await renderWordCard(
      _compactContent(phonetic: '/dɪˈpɒzɪt/'),
    );
    final definition = await renderWordCard(
      _compactContent(translation: 'n. 押金；存款'),
    );

    final blankImage = image.decodePng(blank.previewPng)!;
    final phoneticInk = _differenceBounds(
      blankImage,
      image.decodePng(phonetic.previewPng)!,
    )!;
    final definitionInk = _differenceBounds(
      blankImage,
      image.decodePng(definition.previewPng)!,
    )!;

    expect(
      phoneticInk.$2 <= definitionInk.$4 && definitionInk.$2 <= phoneticInk.$4,
      isTrue,
    );
  });

  test(
    'Chinese example translation is visible below the English example',
    () async {
      final untranslated = await renderWordCard(
        _compactContent(example: 'Pay a deposit to reserve it.'),
      );
      final translated = await renderWordCard(
        _compactContent(
          example: 'Pay a deposit to reserve it.',
          exampleTranslation: '支付押金即可预留。',
        ),
      );

      final difference = _differenceBounds(
        image.decodePng(untranslated.previewPng)!,
        image.decodePng(translated.previewPng)!,
      );

      expect(difference, isNotNull);
      expect(difference!.$2, greaterThan(100));
      expect(difference.$4, lessThan(152));
    },
  );
}

WordCardContent _compactContent({
  String phonetic = '',
  String translation = '',
  String example = '',
  String exampleTranslation = '',
}) {
  return WordCardContent(
    word: 'deposit',
    phonetic: phonetic,
    translation: translation,
    example: example,
    exampleTranslation: exampleTranslation,
    frequency: 102,
    reviewLabel: '新词',
    position: 1,
    total: 8,
  );
}

(int, int, int, int)? _differenceBounds(image.Image left, image.Image right) {
  var minX = left.width;
  var minY = left.height;
  var maxX = -1;
  var maxY = -1;
  for (var y = 0; y < left.height; y++) {
    for (var x = 0; x < left.width; x++) {
      if (left.getPixel(x, y) == right.getPixel(x, y)) continue;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
  }
  return maxX < 0 ? null : (minX, minY, maxX, maxY);
}
