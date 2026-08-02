import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:quotewords/core/ble/quote_protocol.dart';
import 'package:quotewords/core/devices/paired_device_store.dart';
import 'package:quotewords/core/image/epaper_image_processor.dart';
import 'package:quotewords/features/words/data/isdc_catalog_parser.dart';
import 'package:quotewords/features/words/data/study_reminder.dart';
import 'package:quotewords/features/words/data/study_session.dart';
import 'package:quotewords/features/words/data/study_settings_store.dart';
import 'package:quotewords/features/words/data/vocabulary_catalog.dart';
import 'package:quotewords/features/words/domain/study_settings.dart';
import 'package:quotewords/features/words/domain/word_card.dart';
import 'package:quotewords/main.dart';

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

class FixedVocabularyCatalog implements VocabularyCatalog {
  FixedVocabularyCatalog(this.words);

  final List<VocabularyWord> words;

  @override
  Future<List<VocabularyWord>> load() async => words;
}

class FailingVocabularyCatalog implements VocabularyCatalog {
  @override
  Future<List<VocabularyWord>> load() async => throw Exception('offline');
}

class MemoryStudyStateStore implements StudyStateStore {
  StudyState value = const StudyState();

  @override
  Future<StudyState> load() async => value;

  @override
  Future<void> save(StudyState state) async => value = state;
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
      QuoteWordsApp(
        studySettingsStore: settings,
        studyReminder: reminder,
        vocabularyCatalog: FixedVocabularyCatalog(const [allocateWord]),
        studyStateStore: MemoryStudyStateStore(),
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

  testWidgets('synced words render and ratings persist before advancing', (
    tester,
  ) async {
    final stateStore = MemoryStudyStateStore();
    final rendered = <WordCardContent>[];

    await tester.pumpWidget(
      QuoteWordsApp(
        vocabularyCatalog: FixedVocabularyCatalog(const [
          allocateWord,
          depositWord,
        ]),
        studyStateStore: stateStore,
        studySettingsStore: MemoryStudySettingsStore()
          ..value = const StudySettings(newWordsPerDay: 2, dailyLimit: 2),
        studyReminder: RecordingStudyReminder(),
        deviceStore: EmptyDeviceStore(),
        wordCardRender: (content) async {
          rendered.add(content);
          return fakeWordCardRender(content);
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(rendered.last.word, 'allocate');
    expect(rendered.last.position, 1);
    expect(rendered.last.total, 2);

    await tester.ensureVisible(find.text('认识'));
    await tester.tap(find.text('认识'));
    await tester.pumpAndSettle();

    expect(stateStore.value.progress['allocate']?.step, 1);
    expect(stateStore.value.currentIndex, 1);
    expect(rendered.last.word, 'deposit');
    expect(rendered.last.position, 2);
  });

  testWidgets('first sync failure keeps the compact fallback card', (
    tester,
  ) async {
    final rendered = <WordCardContent>[];

    await tester.pumpWidget(
      QuoteWordsApp(
        vocabularyCatalog: FailingVocabularyCatalog(),
        studyStateStore: MemoryStudyStateStore(),
        studySettingsStore: MemoryStudySettingsStore(),
        studyReminder: RecordingStudyReminder(),
        deviceStore: EmptyDeviceStore(),
        wordCardRender: (content) async {
          rendered.add(content);
          return fakeWordCardRender(content);
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(rendered.last.word, 'deposit');
    expect(find.text('使用内置词卡'), findsOneWidget);
  });

  testWidgets('increasing new words adds more cards to today', (tester) async {
    final rendered = <WordCardContent>[];

    await tester.pumpWidget(
      QuoteWordsApp(
        vocabularyCatalog: FixedVocabularyCatalog(const [
          allocateWord,
          depositWord,
        ]),
        studyStateStore: MemoryStudyStateStore(),
        studySettingsStore: MemoryStudySettingsStore()
          ..value = const StudySettings(newWordsPerDay: 1),
        studyReminder: RecordingStudyReminder(),
        deviceStore: EmptyDeviceStore(),
        wordCardRender: (content) async {
          rendered.add(content);
          return fakeWordCardRender(content);
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('认识'));
    await tester.tap(find.text('认识'));
    await tester.pumpAndSettle();
    expect(find.text('今日学习已完成'), findsOneWidget);

    await tester.tap(find.byTooltip('学习设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('增加每日新词'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(rendered.last.word, 'deposit');
    expect(rendered.last.position, 2);
    expect(rendered.last.total, 2);
  });

  testWidgets('image workflow remains separate from word study', (
    tester,
  ) async {
    await tester.pumpWidget(
      QuoteWordsApp(
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

const allocateWord = VocabularyWord(
  id: 'allocate',
  word: 'allocate',
  phonetic: '/ˈæləkeɪt/',
  translation: 'v. 分配；划拨',
  example: 'Allocate funds carefully.',
  frequency: 68,
);

const depositWord = VocabularyWord(
  id: 'deposit',
  word: 'deposit',
  phonetic: '/dɪˈpɒzɪt/',
  translation: 'n. 押金；存款',
  example: 'Pay a deposit to reserve it.',
  frequency: 60,
);
