import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/image/epaper_image_processor.dart';
import '../domain/word_card.dart';

class WordCardLayout {
  const WordCardLayout({
    required this.wordFontSize,
    required this.measuredWordWidth,
    required this.wordMaxWidth,
    required this.wordIsTruncated,
    required this.wordLines,
  });

  static const safeWordWidth = 272.0;

  factory WordCardLayout.resolve(WordCardContent content) {
    var fontSize = 29.0;
    var measurement = _measureWord(content.word, fontSize, maxLines: 1);
    while (measurement.didOverflow && fontSize > 14) {
      fontSize -= 1;
      measurement = _measureWord(content.word, fontSize, maxLines: 1);
    }
    var lines = 1;
    if (measurement.didOverflow) {
      lines = 2;
      measurement = _measureWord(content.word, fontSize, maxLines: lines);
    }
    return WordCardLayout(
      wordFontSize: fontSize,
      measuredWordWidth: measurement.maxLineWidth,
      wordMaxWidth: safeWordWidth,
      wordIsTruncated: measurement.didOverflow,
      wordLines: lines,
    );
  }

  final double wordFontSize;
  final double measuredWordWidth;
  final double wordMaxWidth;
  final bool wordIsTruncated;
  final int wordLines;
}

Future<ProcessedImage> renderWordCard(WordCardContent content) async {
  const width = 296;
  const height = 152;
  const ink = Color(0xff111111);
  final layout = WordCardLayout.resolve(content);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 296, 152),
    Paint()..color = Colors.white,
  );

  _paintText(
    canvas,
    content.reviewLabel,
    const Offset(12, 7),
    fontSize: 9,
    weight: FontWeight.w700,
    color: ink,
  );
  final progress = [
    if (content.frequency > 0) '${content.frequency}次',
    '${content.position.toString().padLeft(2, '0')}/${content.total.toString().padLeft(2, '0')}',
  ].join('  |  ');
  _paintText(
    canvas,
    progress,
    const Offset(284, 7),
    fontSize: 9,
    weight: FontWeight.w600,
    color: ink,
    align: TextAlign.right,
    anchorRight: true,
  );
  canvas.drawLine(
    const Offset(12, 22),
    const Offset(284, 22),
    Paint()
      ..color = ink
      ..strokeWidth = 1,
  );

  _paintText(
    canvas,
    content.word,
    const Offset(12, 27),
    maxWidth: 272,
    maxLines: layout.wordLines,
    fontSize: layout.wordFontSize,
    weight: FontWeight.w800,
    color: ink,
  );
  final denseWord = layout.wordLines > 1;
  _paintText(
    canvas,
    content.phonetic,
    Offset(13, denseWord ? 69 : 62),
    fontSize: 10.5,
    weight: FontWeight.w500,
    color: ink,
  );
  _paintText(
    canvas,
    content.translation,
    Offset(12, denseWord ? 88 : 80),
    maxWidth: 272,
    fontSize: 13,
    weight: FontWeight.w700,
    color: ink,
  );
  if (!denseWord) {
    canvas.drawLine(
      const Offset(12, 102),
      const Offset(284, 102),
      Paint()
        ..color = const Color(0xff777777)
        ..strokeWidth = 0.75,
    );
    _paintText(
      canvas,
      content.example,
      const Offset(12, 109),
      maxWidth: 272,
      maxLines: 2,
      fontSize: 10.5,
      height: 1.2,
      weight: FontWeight.w500,
      color: ink,
    );
  }

  final picture = recorder.endRecording();
  final rendered = await picture.toImage(width, height);
  final pngData = await rendered.toByteData(format: ui.ImageByteFormat.png);
  if (pngData == null) throw StateError('无法生成词卡图片');
  return processImage(
    pngData.buffer.asUint8List(),
    const ImageProcessingOptions(
      fit: ImageFitMode.cover,
      dither: DitherMode.threshold,
      threshold: 180,
    ),
  );
}

_WordMeasurement _measureWord(
  String text,
  double fontSize, {
  required int maxLines,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: Colors.black,
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: maxLines,
    textScaler: TextScaler.noScaling,
  )..layout(maxWidth: WordCardLayout.safeWordWidth);
  final widths = painter.computeLineMetrics().map((line) => line.width);
  return _WordMeasurement(
    maxLineWidth: widths.isEmpty ? 0 : widths.reduce((a, b) => a > b ? a : b),
    didOverflow: painter.didExceedMaxLines,
  );
}

class _WordMeasurement {
  const _WordMeasurement({
    required this.maxLineWidth,
    required this.didOverflow,
  });

  final double maxLineWidth;
  final bool didOverflow;
}

void _paintText(
  Canvas canvas,
  String text,
  Offset offset, {
  required double fontSize,
  required FontWeight weight,
  required Color color,
  double maxWidth = double.infinity,
  int maxLines = 1,
  double height = 1,
  TextAlign align = TextAlign.left,
  bool anchorRight = false,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: weight,
        height: height,
        letterSpacing: 0,
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: align,
    maxLines: maxLines,
    ellipsis: maxLines > 1 ? '…' : null,
    textScaler: TextScaler.noScaling,
  )..layout(maxWidth: maxWidth);
  painter.paint(
    canvas,
    anchorRight ? Offset(offset.dx - painter.width, offset.dy) : offset,
  );
}
