import 'dart:convert';
import 'dart:typed_data';

import 'package:html/parser.dart' as html;

typedef SegmentDecoder = Future<Uint8List> Function(Uint8List bytes);

class VocabularyWord {
  const VocabularyWord({
    required this.id,
    required this.word,
    required this.phonetic,
    required this.translation,
    required this.example,
    this.exampleTranslation = '',
    required this.frequency,
  });

  factory VocabularyWord.fromJson(Map<String, Object?> json) {
    return VocabularyWord(
      id: json['id']! as String,
      word: json['word']! as String,
      phonetic: json['phonetic']! as String,
      translation: json['translation']! as String,
      example: json['example']! as String,
      exampleTranslation: _asText(json['exampleTranslation']),
      frequency: json['frequency']! as int,
    );
  }

  final String id;
  final String word;
  final String phonetic;
  final String translation;
  final String example;
  final String exampleTranslation;
  final int frequency;

  Map<String, Object> toJson() => {
    'id': id,
    'word': word,
    'phonetic': phonetic,
    'translation': translation,
    'example': example,
    'exampleTranslation': exampleTranslation,
    'frequency': frequency,
  };
}

class IsdcCatalogParser {
  IsdcCatalogParser({required SegmentDecoder decodeSegment})
    : _decodeSegment = decodeSegment;

  final SegmentDecoder _decodeSegment;

  Future<List<VocabularyWord>> parse(
    String source, {
    required int minimumFrequency,
  }) async {
    final document = html.parse(source);
    final payload = document.querySelector('#asp-data')?.text.trim();
    if (payload == null || payload.isEmpty) {
      throw const FormatException('词典页面缺少 asp-data 数据');
    }

    final decoded = BytesBuilder(copy: false);
    for (final segment in payload.split('\n')) {
      final encoded = segment.trim();
      if (encoded.isEmpty) continue;
      decoded.add(await _decodeSegment(_decodeBase85(encoded)));
    }

    final root = jsonDecode(utf8.decode(decoded.takeBytes()));
    if (root is! Map<String, dynamic> || root['g'] is! List) {
      throw const FormatException('词典数据结构无效');
    }

    final byId = <String, VocabularyWord>{};
    for (final rawGroup in root['g']! as List) {
      if (rawGroup is! Map || rawGroup['ws'] is! List) continue;
      for (final rawWord in rawGroup['ws']! as List) {
        if (rawWord is! Map) continue;
        final frequency = _asInt(rawWord['oc']);
        final word = _asText(rawWord['w']);
        final translation = _asText(rawWord['t']);
        if (frequency < minimumFrequency ||
            word.isEmpty ||
            translation.isEmpty) {
          continue;
        }
        final id = word.toLowerCase();
        final phonetic = _normalizePhonetic(_asText(rawWord['p']));
        final entry = VocabularyWord(
          id: id,
          word: word,
          phonetic: phonetic,
          translation: translation,
          example: _asText(rawWord['e']),
          exampleTranslation: _asText(rawWord['ec']),
          frequency: frequency,
        );
        final previous = byId[id];
        if (previous == null || entry.frequency > previous.frequency) {
          byId[id] = entry;
        }
      }
    }

    final words = byId.values.toList()
      ..sort((left, right) {
        final frequency = right.frequency.compareTo(left.frequency);
        return frequency != 0 ? frequency : left.id.compareTo(right.id);
      });
    return List.unmodifiable(words);
  }
}

Uint8List _decodeBase85(String source) {
  final alphabet = String.fromCharCodes(
    [
      for (var code = 33; code <= 126; code++)
        if (code != 34 && code != 39 && code != 60) code,
    ].take(85),
  );
  final indexes = <int, int>{
    for (var index = 0; index < alphabet.length; index++)
      alphabet.codeUnitAt(index): index,
  };
  final output = BytesBuilder(copy: false);
  for (var offset = 0; offset < source.length; offset += 5) {
    final count = (source.length - offset).clamp(0, 5);
    final byteCount = count * 4 ~/ 5;
    var value = 0;
    for (var index = 0; index < count; index++) {
      final digit = indexes[source.codeUnitAt(offset + index)];
      if (digit == null) throw const FormatException('词典 Base85 数据无效');
      value = value * 85 + digit;
    }
    for (var index = count; index < 5; index++) {
      value = value * 85 + 84;
    }
    for (var index = 0; index < byteCount; index++) {
      output.addByte(value ~/ _powersOf256[3 - index] % 256);
    }
  }
  return output.takeBytes();
}

const _powersOf256 = [1, 256, 65536, 16777216];

int _asInt(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _asText(Object? value) => value?.toString().trim() ?? '';

String _normalizePhonetic(String value) {
  final phonetic = value.replaceAll(RegExp(r'^/+|/+$'), '');
  return phonetic.isEmpty ? '' : '/$phonetic/';
}
