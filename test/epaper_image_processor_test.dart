import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:quotewords/core/ble/quote_protocol.dart';
import 'package:quotewords/core/image/epaper_image_processor.dart';

Uint8List solidPng(int value) {
  final source = image.Image(width: 8, height: 8, numChannels: 3)
    ..clear(image.ColorRgb8(value, value, value));
  return Uint8List.fromList(image.encodePng(source));
}

void main() {
  test('treats the Quote/0 landscape orientation as zero degrees', () {
    expect(const ImageProcessingOptions().rotation, 0);
  });

  test('solid white and black encode to the expected frame bits', () async {
    final white = await processImage(
      solidPng(255),
      const ImageProcessingOptions(
        fit: ImageFitMode.cover,
        dither: DitherMode.threshold,
      ),
    );
    final black = await processImage(
      solidPng(0),
      const ImageProcessingOptions(
        fit: ImageFitMode.cover,
        dither: DitherMode.threshold,
      ),
    );

    expect(white.frame.length, QuoteProtocol.frameSize);
    expect(white.frame.every((value) => value == 0xff), isTrue);
    expect(black.frame.every((value) => value == 0x00), isTrue);
    final preview = image.decodePng(white.previewPng)!;
    expect((preview.width, preview.height), (296, 152));
  });

  test(
    'zero-degree landscape preview maps to the 270-degree panel frame',
    () async {
      final source = image.Image(width: 296, height: 152, numChannels: 3)
        ..clear(image.ColorRgb8(255, 255, 255));
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 8; x++) {
          source.setPixelRgb(x, y, 0, 0, 0);
        }
      }

      final result = await processImage(
        Uint8List.fromList(image.encodePng(source)),
        const ImageProcessingOptions(
          fit: ImageFitMode.cover,
          dither: DitherMode.threshold,
        ),
      );
      final preview = image.decodePng(result.previewPng)!;

      expect(preview.getPixel(0, 0).r, 0);
      expect(preview.getPixel(preview.width - 1, 0).r, 255);
      expect(result.frame[295 * (QuoteProtocol.frameWidth ~/ 8)], 0x00);
      expect(result.frame[0], 0xff);
    },
  );

  test('optimized Atkinson output is deterministic', () async {
    final source = image.Image(width: 32, height: 48, numChannels: 3);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        final value = ((x + y) / (source.width + source.height) * 255).round();
        source.setPixelRgb(x, y, value, value, value);
      }
    }
    final bytes = Uint8List.fromList(image.encodePng(source));
    const options = ImageProcessingOptions(
      fit: ImageFitMode.cover,
      dither: DitherMode.atkinson,
      rotation: 90,
      threshold: 137,
    );

    final first = await processImage(bytes, options);
    final second = await processImage(bytes, options);

    expect(first.frame, second.frame);
    expect(first.frame.toSet().containsAll({0, 0xff}), isTrue);
  });

  test(
    'Atkinson separates low-contrast regions for a readable panel',
    () async {
      final source = image.Image(width: 296, height: 152, numChannels: 3);
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          final value = x < source.width ~/ 2 ? 112 : 144;
          source.setPixelRgb(x, y, value, value, value);
        }
      }

      final result = await processImage(
        Uint8List.fromList(image.encodePng(source)),
        const ImageProcessingOptions(
          fit: ImageFitMode.cover,
          dither: DitherMode.atkinson,
        ),
      );
      final preview = image.decodePng(result.previewPng)!;
      final darkRatio = _blackRatio(preview, left: 20, right: 120);
      final lightRatio = _blackRatio(preview, left: 176, right: 276);

      expect(darkRatio - lightRatio, greaterThan(0.75));
    },
  );
}

double _blackRatio(
  image.Image source, {
  required int left,
  required int right,
}) {
  var black = 0;
  var total = 0;
  for (var y = 0; y < source.height; y++) {
    for (var x = left; x < right; x++) {
      if (source.getPixel(x, y).r == 0) black++;
      total++;
    }
  }
  return black / total;
}
