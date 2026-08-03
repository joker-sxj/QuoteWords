import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;

import '../ble/quote_protocol.dart';

enum ImageFitMode { contain, cover }

enum DitherMode { atkinson, threshold }

class ImageProcessingOptions {
  const ImageProcessingOptions({
    this.fit = ImageFitMode.contain,
    this.dither = DitherMode.atkinson,
    this.rotation = 0,
    this.threshold = 128,
  });

  final ImageFitMode fit;
  final DitherMode dither;
  final int rotation;
  final int threshold;

  Map<String, Object> toMessage(Uint8List source) => {
    'source': source,
    'fit': fit.index,
    'dither': dither.index,
    'rotation': rotation,
    'threshold': threshold,
  };
}

class ProcessedImage {
  const ProcessedImage({required this.previewPng, required this.frame});

  final Uint8List previewPng;
  final Uint8List frame;
}

Future<ProcessedImage> processImage(
  Uint8List source,
  ImageProcessingOptions options,
) async {
  final result = await compute(_process, options.toMessage(source));
  return ProcessedImage(
    previewPng: result['preview']! as Uint8List,
    frame: result['frame']! as Uint8List,
  );
}

Map<String, Object> _process(Map<String, Object> message) {
  final decoded = image.decodeImage(message['source']! as Uint8List);
  if (decoded == null) throw const FormatException('无法解码这张图片');

  var oriented = image.bakeOrientation(decoded);
  const panelRotation = 270;
  final userRotation = message['rotation']! as int;
  final physicalRotation = (userRotation + panelRotation) % 360;
  if (physicalRotation != 0) {
    oriented = image.copyRotate(
      oriented,
      angle: physicalRotation,
      interpolation: image.Interpolation.cubic,
    );
  }

  const width = QuoteProtocol.frameWidth;
  const height = QuoteProtocol.frameHeight;
  final fit = ImageFitMode.values[message['fit']! as int];
  final scale = fit == ImageFitMode.cover
      ? math.max(width / oriented.width, height / oriented.height)
      : math.min(width / oriented.width, height / oriented.height);
  final resized = image.copyResize(
    oriented,
    width: math.max(1, (oriented.width * scale).round()),
    height: math.max(1, (oriented.height * scale).round()),
    interpolation: image.Interpolation.cubic,
  );

  late image.Image canvas;
  if (fit == ImageFitMode.cover) {
    canvas = image.copyCrop(
      resized,
      x: (resized.width - width) ~/ 2,
      y: (resized.height - height) ~/ 2,
      width: width,
      height: height,
    );
  } else {
    canvas = image.Image(width: width, height: height, numChannels: 4);
    image.fill(canvas, color: image.ColorRgba8(255, 255, 255, 255));
    image.compositeImage(
      canvas,
      resized,
      dstX: (width - resized.width) ~/ 2,
      dstY: (height - resized.height) ~/ 2,
    );
  }

  final luma = Float64List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final pixel = canvas.getPixel(x, y);
      final alpha = pixel.aNormalized;
      final red = pixel.r * alpha + 255 * (1 - alpha);
      final green = pixel.g * alpha + 255 * (1 - alpha);
      final blue = pixel.b * alpha + 255 * (1 - alpha);
      luma[y * width + x] = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
    }
  }

  final mode = DitherMode.values[message['dither']! as int];
  if (mode == DitherMode.atkinson) _stretchContrast(luma);

  final output = image.Image(width: width, height: height, numChannels: 3);
  final frame = Uint8List(QuoteProtocol.frameSize)
    ..fillRange(0, QuoteProtocol.frameSize, 0xff);
  final threshold = message['threshold']! as int;

  for (var y = 0; y < height; y++) {
    final reverse = mode == DitherMode.atkinson && y.isOdd;
    final start = reverse ? width - 1 : 0;
    final end = reverse ? -1 : width;
    final step = reverse ? -1 : 1;
    for (var x = start; x != end; x += step) {
      final index = y * width + x;
      final oldValue = luma[index];
      var decisionValue = oldValue;
      if (mode == DitherMode.atkinson) {
        decisionValue += _jitter(x, y);
      }
      final black = decisionValue < threshold;
      final newValue = black ? 0 : 255;
      if (black) {
        frame[y * (width ~/ 8) + (x >> 3)] &= ~(0x80 >> (x & 7));
      }
      output.setPixelRgb(x, y, newValue, newValue, newValue);

      if (mode == DitherMode.atkinson) {
        final share = (oldValue - newValue) / 8;
        final direction = reverse ? -1 : 1;
        _add(luma, x + direction, y, share);
        _add(luma, x + 2 * direction, y, share);
        _add(luma, x - direction, y + 1, share);
        _add(luma, x, y + 1, share);
        _add(luma, x + direction, y + 1, share);
        _add(luma, x, y + 2, share);
      }
    }
  }

  final landscapePreview = image.copyRotate(output, angle: 90);
  return {
    'preview': Uint8List.fromList(image.encodePng(landscapePreview, level: 1)),
    'frame': frame,
  };
}

void _stretchContrast(Float64List values) {
  final histogram = List<int>.filled(256, 0);
  for (final value in values) {
    histogram[value.round().clamp(0, 255)]++;
  }

  final lowTarget = (values.length * 0.01).floor();
  final highTarget = (values.length * 0.99).ceil();
  var cumulative = 0;
  var low = 0;
  var high = 255;
  for (var value = 0; value < histogram.length; value++) {
    cumulative += histogram[value];
    if (cumulative > lowTarget) {
      low = value;
      break;
    }
  }
  cumulative = 0;
  for (var value = 0; value < histogram.length; value++) {
    cumulative += histogram[value];
    if (cumulative >= highTarget) {
      high = value;
      break;
    }
  }
  if (high - low < 16) return;

  final scale = 255 / (high - low);
  for (var index = 0; index < values.length; index++) {
    values[index] = ((values[index] - low) * scale).clamp(0, 255);
  }
}

double _jitter(int x, int y) {
  var hash =
      (((x + 1) * 0x1f123bb5) & 0xffffffff) ^
      (((y + 1) * 0x5f356495) & 0xffffffff);
  hash ^= hash >>> 15;
  return ((hash & 255) / 255 - 0.5) * 16;
}

void _add(Float64List values, int x, int y, double error) {
  if (x < 0 ||
      x >= QuoteProtocol.frameWidth ||
      y < 0 ||
      y >= QuoteProtocol.frameHeight) {
    return;
  }
  values[y * QuoteProtocol.frameWidth + x] += error;
}
