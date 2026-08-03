import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/ble/quote_ble_client.dart';
import '../../core/devices/paired_device_store.dart';
import '../../core/image/epaper_image_processor.dart';
import 'data/isdc_catalog_parser.dart';
import 'data/study_reminder.dart';
import 'data/study_session.dart';
import 'data/study_settings_store.dart';
import 'data/vocabulary_catalog.dart';
import 'domain/review_scheduler.dart';
import 'domain/study_settings.dart';
import 'domain/word_card.dart';
import 'rendering/word_card_renderer.dart';

class WordStudyScreen extends StatefulWidget {
  const WordStudyScreen({
    super.key,
    required this.bleClient,
    required this.deviceStore,
    required this.settingsStore,
    required this.reminder,
    required this.vocabularyCatalog,
    required this.studyStateStore,
    this.cardRender = renderWordCard,
  });

  final QuoteBleClient bleClient;
  final DeviceStore deviceStore;
  final StudySettingsStore settingsStore;
  final StudyReminder reminder;
  final VocabularyCatalog vocabularyCatalog;
  final StudyStateStore studyStateStore;
  final WordCardRender cardRender;

  @override
  State<WordStudyScreen> createState() => _WordStudyScreenState();
}

class _WordStudyScreenState extends State<WordStudyScreen> {
  static const _fallbackWords = <VocabularyWord>[
    VocabularyWord(
      id: 'deposit',
      word: 'deposit',
      phonetic: '/dɪˈpɒzɪt/',
      translation: 'n. 押金；存款',
      example: 'Pay a deposit to reserve it.',
      frequency: 102,
    ),
    VocabularyWord(
      id: 'allocate',
      word: 'allocate',
      phonetic: '/ˈæləkeɪt/',
      translation: 'v. 分配；划拨',
      example: 'The council allocated funds to housing.',
      frequency: 68,
    ),
    VocabularyWord(
      id: 'fluctuate',
      word: 'fluctuate',
      phonetic: '/ˈflʌktʃueɪt/',
      translation: 'v. 波动；起伏',
      example: 'Demand tends to fluctuate during the year.',
      frequency: 45,
    ),
  ];

  StudySettings _settings = const StudySettings();
  StudySession? _session;
  ProcessedImage? _processed;
  bool _loading = true;
  bool _sending = false;
  bool _usingFallback = false;
  String _phase = '正在准备词卡';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final settings = await widget.settingsStore.load();
      if (!mounted) return;
      _settings = settings;
      final wordsFuture = _loadVocabulary();
      await _renderLoadingCard(settings);
      await widget.reminder.schedule(settings);
      final words = await wordsFuture;
      final session = StudySession(
        words: words,
        store: widget.studyStateStore,
        settings: settings,
      );
      await session.load();
      _session = session;
      await _renderCurrent();
    } catch (error) {
      if (mounted) setState(() => _phase = '词卡准备失败');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<VocabularyWord>> _loadVocabulary() async {
    try {
      final words = await widget.vocabularyCatalog.load();
      if (words.isEmpty) throw const FormatException('词库为空');
      return words;
    } catch (_) {
      _usingFallback = true;
      return _fallbackWords;
    }
  }

  Future<void> _renderLoadingCard(StudySettings settings) async {
    final source = _fallbackWords.first;
    final rendered = await widget.cardRender(
      WordCardContent(
        word: source.word,
        phonetic: source.phonetic,
        translation: source.translation,
        example: source.example,
        frequency: source.frequency,
        reviewLabel: '新词',
        position: 1,
        total: settings.newWordsPerDay,
      ),
    );
    if (!mounted) return;
    setState(() {
      _processed = rendered;
      _phase = '正在更新词库';
    });
  }

  WordCardContent? get _content {
    final session = _session;
    final source = session?.current;
    if (session == null || source == null) return null;
    return WordCardContent(
      word: source.word,
      phonetic: source.phonetic,
      translation: source.translation,
      example: source.example,
      frequency: source.frequency,
      reviewLabel: session.isReview(source.id) ? '复习' : '新词',
      position: session.currentIndex + 1,
      total: session.queue.length,
    );
  }

  Future<void> _renderCurrent() async {
    final content = _content;
    if (content == null) {
      if (!mounted) return;
      setState(() {
        _processed = null;
        _phase = '今日学习已完成';
      });
      return;
    }
    final rendered = await widget.cardRender(content);
    if (!mounted) return;
    setState(() {
      _processed = rendered;
      _phase = _usingFallback ? '使用内置词卡' : '词卡已就绪';
    });
  }

  Future<void> _openSettings() async {
    final settings = await showModalBottomSheet<StudySettings>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _StudySettingsSheet(initial: _settings),
    );
    if (settings == null) return;
    await _session?.updateSettings(settings);
    await widget.settingsStore.save(settings);
    await widget.reminder.schedule(settings);
    if (!mounted) return;
    setState(() => _settings = settings);
    await _renderCurrent();
  }

  Future<void> _rate(RecallRating rating) async {
    final session = _session;
    if (_loading || _sending || session?.current == null) return;
    setState(() => _loading = true);
    try {
      await session!.rate(rating);
      await _renderCurrent();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final frame = _processed?.frame;
    if (frame == null || _sending) return;
    setState(() {
      _sending = true;
      _phase = '正在查找设备';
    });
    try {
      final devices = await widget.deviceStore.loadDevices();
      final selectedMac = await widget.deviceStore.loadLastSelectedMac();
      final selected = devices
          .where((device) => device.mac == selectedMac)
          .firstOrNull;
      if (selected == null) throw StateError('请先在图片页添加并选择设备');
      final credential = await widget.deviceStore.loadCredential(selected.mac);
      if (credential == null) throw StateError('本机缺少设备凭证');
      final target = await widget.bleClient.findByMac(selected.mac);
      if (target == null) throw StateError('${selected.name} 当前离线');
      await widget.bleClient.upload(
        target,
        credential,
        frame,
        onProgress: (_, phase) {
          if (mounted) setState(() => _phase = phase);
        },
      );
    } catch (error) {
      if (mounted) {
        final message = error is StateError ? error.message : error.toString();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
        setState(() => _phase = '发送失败');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('今日词卡'),
        actions: [
          IconButton(
            onPressed: _openSettings,
            tooltip: '学习设置',
            icon: const Icon(Icons.tune),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 18,
                    runSpacing: 6,
                    children: [
                      Text('新词 ${_settings.newWordsPerDay}'),
                      Text('上限 ${_settings.dailyLimit}'),
                      Text(
                        '${_settings.reminderHour.toString().padLeft(2, '0')}:${_settings.reminderMinute.toString().padLeft(2, '0')}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  AspectRatio(
                    aspectRatio: 296 / 152,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(
                          color: const Color(0xff5d645d),
                          width: 2,
                        ),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_processed != null)
                            Image.memory(
                              _processed!.previewPng,
                              fit: BoxFit.fill,
                              filterQuality: FilterQuality.none,
                              gaplessPlayback: true,
                              semanticLabel:
                                  '${_content?.word ?? _fallbackWords.first.word} 词卡预览',
                            ),
                          if (_loading)
                            const ColoredBox(
                              color: Color(0x55ffffff),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _phase,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _processed == null || _sending
                            ? null
                            : _send,
                        icon: const Icon(Icons.send),
                        label: const Text('显示到设备'),
                      ),
                    ],
                  ),
                  const Divider(height: 30),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 3.2,
                    children: [
                      OutlinedButton(
                        onPressed: () => _rate(RecallRating.forgotten),
                        child: const Text('忘记'),
                      ),
                      OutlinedButton(
                        onPressed: () => _rate(RecallRating.hard),
                        child: const Text('模糊'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => _rate(RecallRating.good),
                        child: const Text('认识'),
                      ),
                      FilledButton(
                        onPressed: () => _rate(RecallRating.easy),
                        child: const Text('熟练'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StudySettingsSheet extends StatefulWidget {
  const _StudySettingsSheet({required this.initial});

  final StudySettings initial;

  @override
  State<_StudySettingsSheet> createState() => _StudySettingsSheetState();
}

class _StudySettingsSheetState extends State<_StudySettingsSheet> {
  late StudySettings _settings = widget.initial;

  void _changeNewWords(int delta) {
    setState(() {
      _settings = _settings.copyWith(
        newWordsPerDay: _settings.newWordsPerDay + delta,
      );
    });
  }

  void _changeLimit(int delta) {
    setState(() {
      _settings = _settings.copyWith(dailyLimit: _settings.dailyLimit + delta);
    });
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _settings.reminderHour,
        minute: _settings.reminderMinute,
      ),
    );
    if (time == null) return;
    setState(() {
      _settings = _settings.copyWith(
        reminderHour: time.hour,
        reminderMinute: time.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('每日学习', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            _NumberStepper(
              label: '每日新词',
              value: _settings.newWordsPerDay,
              onDecrease: () => _changeNewWords(-1),
              onIncrease: () => _changeNewWords(1),
              decreaseTooltip: '减少每日新词',
              increaseTooltip: '增加每日新词',
            ),
            _NumberStepper(
              label: '每日上限',
              value: _settings.dailyLimit,
              onDecrease: () => _changeLimit(-1),
              onIncrease: () => _changeLimit(1),
              decreaseTooltip: '减少每日上限',
              increaseTooltip: '增加每日上限',
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('提醒时间'),
              trailing: TextButton(
                onPressed: _pickTime,
                child: Text(
                  '${_settings.reminderHour.toString().padLeft(2, '0')}:${_settings.reminderMinute.toString().padLeft(2, '0')}',
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(context, _settings),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberStepper extends StatelessWidget {
  const _NumberStepper({
    required this.label,
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
    required this.decreaseTooltip,
    required this.increaseTooltip,
  });

  final String label;
  final int value;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final String decreaseTooltip;
  final String increaseTooltip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          Expanded(child: Text(label)),
          IconButton(
            onPressed: onDecrease,
            tooltip: decreaseTooltip,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 42,
            child: Text(
              value.toString(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            onPressed: onIncrease,
            tooltip: increaseTooltip,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
