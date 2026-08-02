import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:quoteimage_mobile/core/ble/quote_protocol.dart';
import 'package:quoteimage_mobile/features/words/domain/word_card.dart';
import 'package:quoteimage_mobile/features/words/rendering/word_card_renderer.dart';

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
}
