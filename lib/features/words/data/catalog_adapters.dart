import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'isdc_catalog_parser.dart';
import 'vocabulary_catalog.dart';

typedef DirectoryProvider = Future<Directory> Function();
typedef PageLoader = Future<String> Function();

class JsonFileVocabularyCatalogCache implements VocabularyCatalogCache {
  JsonFileVocabularyCatalogCache({DirectoryProvider? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static const fileName = 'ielts-catalog.json';
  final DirectoryProvider _directoryProvider;

  @override
  Future<CatalogSnapshot?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic> || json['words'] is! List) return null;
      return CatalogSnapshot(
        syncedAt: DateTime.parse(json['syncedAt']! as String).toUtc(),
        words: List.unmodifiable(
          (json['words']! as List).whereType<Map<String, dynamic>>().map(
            VocabularyWord.fromJson,
          ),
        ),
      );
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  @override
  Future<void> write(CatalogSnapshot value) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'syncedAt': value.syncedAt.toUtc().toIso8601String(),
        'words': value.words.map((word) => word.toJson()).toList(),
      }),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<File> _file() async {
    final directory = await _directoryProvider();
    return File('${directory.path}/$fileName');
  }
}

class IsdcVocabularyCatalogSource implements VocabularyCatalogSource {
  IsdcVocabularyCatalogSource({
    required PageLoader loadPage,
    required SegmentDecoder decodeSegment,
  }) : _loadPage = loadPage,
       _parser = IsdcCatalogParser(decodeSegment: decodeSegment);

  final PageLoader _loadPage;
  final IsdcCatalogParser _parser;

  @override
  Future<List<VocabularyWord>> fetch() async {
    return _parser.parse(await _loadPage(), minimumFrequency: 40);
  }
}

Future<String> downloadIsdcPage() async {
  final response = await http
      .get(Uri.parse('https://isdc.pages.dev/'))
      .timeout(const Duration(seconds: 90));
  if (response.statusCode != HttpStatus.ok) {
    throw HttpException('词典更新失败：HTTP ${response.statusCode}');
  }
  return utf8.decode(response.bodyBytes);
}

class AndroidBrotliDecoder {
  static const _channel = MethodChannel('tech.undef.quoteimage/brotli');

  Future<Uint8List> call(Uint8List bytes) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('词典同步目前仅支持 Android');
    }
    final output = await _channel.invokeMethod<Uint8List>('decompress', bytes);
    if (output == null) throw const FormatException('Brotli 解压未返回数据');
    return output;
  }
}
