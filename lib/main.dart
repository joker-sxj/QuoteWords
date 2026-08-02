import 'package:flutter/material.dart';

import 'core/ble/quote_ble_client.dart';
import 'core/devices/paired_device_store.dart';
import 'features/editor/editor_screen.dart';
import 'features/words/data/catalog_adapters.dart';
import 'features/words/data/study_reminder.dart';
import 'features/words/data/study_session.dart';
import 'features/words/data/study_settings_store.dart';
import 'features/words/data/study_state_store.dart';
import 'features/words/data/vocabulary_catalog.dart';
import 'features/words/rendering/word_card_renderer.dart';
import 'features/words/word_study_screen.dart';

enum HomeSection { words, image }

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const QuoteWordsApp());
}

class QuoteWordsApp extends StatelessWidget {
  const QuoteWordsApp({
    super.key,
    this.bleClient,
    this.deviceStore,
    this.studySettingsStore,
    this.studyReminder,
    this.vocabularyCatalog,
    this.studyStateStore,
    this.wordCardRender,
    this.initialSection = HomeSection.words,
  });

  final QuoteBleClient? bleClient;
  final DeviceStore? deviceStore;
  final StudySettingsStore? studySettingsStore;
  final StudyReminder? studyReminder;
  final VocabularyCatalog? vocabularyCatalog;
  final StudyStateStore? studyStateStore;
  final WordCardRender? wordCardRender;
  final HomeSection initialSection;

  @override
  Widget build(BuildContext context) {
    const colors = ColorScheme.light(
      primary: Color(0xff176b4d),
      onPrimary: Colors.white,
      secondary: Color(0xffb7791f),
      onSecondary: Colors.white,
      surface: Color(0xfffbfcfa),
      onSurface: Color(0xff20231f),
      error: Color(0xffa33428),
      onError: Colors.white,
      outline: Color(0xff747b73),
    );
    return MaterialApp(
      title: 'QuoteWords',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colors,
        scaffoldBackgroundColor: colors.surface,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xfffbfcfa),
          foregroundColor: Color(0xff20231f),
          elevation: 0,
          scrolledUnderElevation: 1,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Color(0xff20231f),
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        cardTheme: const CardThemeData(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(6)),
            side: BorderSide(color: Color(0xffcbd0c9)),
          ),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            textStyle: WidgetStateProperty.all(
              const TextStyle(fontSize: 13, letterSpacing: 0),
            ),
            shape: WidgetStateProperty.all(
              const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
            ),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
          ),
        ),
      ),
      home: _QuoteHome(
        bleClient: bleClient ?? QuoteBleClient(),
        deviceStore: deviceStore ?? PersistentDeviceStore(),
        studySettingsStore:
            studySettingsStore ?? PersistentStudySettingsStore(),
        studyReminder: studyReminder ?? LocalStudyReminder(),
        vocabularyCatalog:
            vocabularyCatalog ??
            CachedVocabularyCatalog(
              cache: JsonFileVocabularyCatalogCache(),
              source: IsdcVocabularyCatalogSource(
                loadPage: downloadIsdcPage,
                decodeSegment: AndroidBrotliDecoder().call,
              ),
            ),
        studyStateStore: studyStateStore ?? JsonFileStudyStateStore(),
        wordCardRender: wordCardRender ?? renderWordCard,
        initialSection: initialSection,
      ),
    );
  }
}

class _QuoteHome extends StatefulWidget {
  const _QuoteHome({
    required this.bleClient,
    required this.deviceStore,
    required this.studySettingsStore,
    required this.studyReminder,
    required this.vocabularyCatalog,
    required this.studyStateStore,
    required this.wordCardRender,
    required this.initialSection,
  });

  final QuoteBleClient bleClient;
  final DeviceStore deviceStore;
  final StudySettingsStore studySettingsStore;
  final StudyReminder studyReminder;
  final VocabularyCatalog vocabularyCatalog;
  final StudyStateStore studyStateStore;
  final WordCardRender wordCardRender;
  final HomeSection initialSection;

  @override
  State<_QuoteHome> createState() => _QuoteHomeState();
}

class _QuoteHomeState extends State<_QuoteHome> {
  late HomeSection _section = widget.initialSection;

  @override
  Widget build(BuildContext context) {
    final page = switch (_section) {
      HomeSection.words => WordStudyScreen(
        bleClient: widget.bleClient,
        deviceStore: widget.deviceStore,
        settingsStore: widget.studySettingsStore,
        reminder: widget.studyReminder,
        vocabularyCatalog: widget.vocabularyCatalog,
        studyStateStore: widget.studyStateStore,
        cardRender: widget.wordCardRender,
      ),
      HomeSection.image => EditorScreen(
        bleClient: widget.bleClient,
        deviceStore: widget.deviceStore,
      ),
    };
    return Scaffold(
      body: page,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _section.index,
        onDestinationSelected: (index) {
          setState(() => _section = HomeSection.values[index]);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school),
            label: '词卡',
          ),
          NavigationDestination(
            icon: Icon(Icons.image_outlined),
            selectedIcon: Icon(Icons.image),
            label: '图片',
          ),
        ],
      ),
    );
  }
}
