import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:quoteimage_mobile/core/ble/quote_protocol.dart';
import 'package:quoteimage_mobile/core/devices/paired_device_store.dart';
import 'package:quoteimage_mobile/core/image/epaper_image_processor.dart';
import 'package:quoteimage_mobile/features/words/data/study_reminder.dart';
import 'package:quoteimage_mobile/features/words/data/study_settings_store.dart';
import 'package:quoteimage_mobile/features/words/domain/study_settings.dart';
import 'package:quoteimage_mobile/features/words/domain/word_card.dart';
import 'package:quoteimage_mobile/main.dart';

class MemoryStudySettingsStore implements StudySettingsStore {
  StudySettings value = const StudySettings();

  @override
  Future<StudySettings> load() async => value;

  @override
  Future<void> save(StudySettings settings) async => value = settings;
}

class RecordingStudyReminder implements StudyReminder {
  StudySettings? scheduled;

  @override
  Future<void> schedule(StudySettings settings) async => scheduled = settings;
}

class EmptyDeviceStore implements DeviceStore {
  @override
  Future<void> deleteCredential(String mac) async {}

  @override
  Future<Uint8List?> loadCredential(String mac) async => null;

  @override
  Future<List<PairedDevice>> loadDevices() async => const [];

  @override
  Future<String?> loadLastSelectedMac() async => null;

  @override
  Future<void> remove(String mac) async {}

  @override
  Future<void> saveCredential(String mac, Uint8List credential) async {}

  @override
  Future<void> select(String? mac) async {}

  @override
  Future<void> upsert(PairedDevice device) async {}
}

Future<ProcessedImage> fakeWordCardRender(WordCardContent content) async {
  final preview = image.Image(width: 296, height: 152, numChannels: 3)
    ..clear(image.ColorRgb8(255, 255, 255));
  return ProcessedImage(
    previewPng: Uint8List.fromList(image.encodePng(preview)),
    frame: Uint8List(QuoteProtocol.frameSize)
      ..fillRange(0, QuoteProtocol.frameSize, 0xff),
  );
}

void main() {
  testWidgets('word study is the default daily workflow', (tester) async {
    final settings = MemoryStudySettingsStore();
    final reminder = RecordingStudyReminder();

    await tester.pumpWidget(
      QuoteImageApp(
        studySettingsStore: settings,
        studyReminder: reminder,
        deviceStore: EmptyDeviceStore(),
        wordCardRender: fakeWordCardRender,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('今日词卡'), findsOneWidget);
    expect(find.text('新词 8'), findsOneWidget);
    expect(find.text('上限 24'), findsOneWidget);
    expect(find.text('09:00'), findsOneWidget);
    expect(find.text('忘记'), findsOneWidget);
    expect(find.text('模糊'), findsOneWidget);
    expect(find.text('认识'), findsOneWidget);
    expect(find.text('熟练'), findsOneWidget);
    expect(find.text('词卡'), findsOneWidget);
    expect(find.text('图片'), findsOneWidget);

    await tester.tap(find.byTooltip('学习设置'));
    await tester.pumpAndSettle();
    expect(find.text('每日学习'), findsOneWidget);
    await tester.tap(find.byTooltip('增加每日新词'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(settings.value.newWordsPerDay, 9);
    expect(reminder.scheduled?.newWordsPerDay, 9);
  });

  testWidgets('image workflow remains separate from word study', (
    tester,
  ) async {
    await tester.pumpWidget(
      QuoteImageApp(
        initialSection: HomeSection.image,
        wordCardRender: fakeWordCardRender,
        deviceStore: EmptyDeviceStore(),
      ),
    );
    await tester.pump();

    expect(find.text('尺寸适配'), findsOneWidget);
    expect(find.text('今日词卡'), findsNothing);
  });
}
