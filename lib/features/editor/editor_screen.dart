import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/ble/quote_ble_client.dart';
import '../../core/ble/quote_protocol.dart';
import '../../core/devices/paired_device_store.dart';
import '../../core/image/epaper_image_processor.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, this.bleClient, this.deviceStore});

  final QuoteBleClient? bleClient;
  final DeviceStore? deviceStore;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final _picker = ImagePicker();
  late final QuoteBleClient _ble;
  late final DeviceStore _store;

  Uint8List? _source;
  String? _fileName;
  ProcessedImage? _processed;
  ImageFitMode _fit = ImageFitMode.contain;
  DitherMode _dither = DitherMode.atkinson;
  int _rotation = 0;
  double _threshold = 128;
  int _processGeneration = 0;
  bool _processing = false;
  bool _scanning = false;
  bool _readingBattery = false;
  bool _sending = false;
  double _sendProgress = 0;
  String _phase = '等待图片';
  List<PairedDevice> _devices = const [];
  PairedDevice? _selectedDevice;
  bool _deviceOnline = false;
  int? _batteryLevel;

  bool get _controlsEnabled => !_processing && !_readingBattery && !_sending;

  @override
  void initState() {
    super.initState();
    _ble = widget.bleClient ?? QuoteBleClient();
    _store = widget.deviceStore ?? PersistentDeviceStore();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    final devices = await _store.loadDevices();
    final selectedMac = await _store.loadLastSelectedMac();
    if (!mounted) return;
    PairedDevice? selected;
    for (final device in devices) {
      if (device.mac == selectedMac) selected = device;
    }
    selected ??= devices.firstOrNull;
    if (selected != null && selectedMac != selected.mac) {
      await _store.select(selected.mac);
    }
    if (!mounted) return;
    setState(() {
      _devices = devices;
      _selectedDevice = selected;
      _deviceOnline = false;
      _batteryLevel = null;
      if (_source == null) {
        _phase = selected == null ? '请添加设备' : '已选择 ${selected.name}';
      }
    });
  }

  Future<void> _pickImage() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 20 * 1024 * 1024) {
      _showError('图片不能超过 20 MiB');
      return;
    }
    setState(() {
      _source = bytes;
      _fileName = file.name;
    });
    await _processImage();
  }

  Future<void> _processImage() async {
    final source = _source;
    if (source == null) return;
    final generation = ++_processGeneration;
    setState(() {
      _processing = true;
      _processed = null;
      _phase = '正在处理图片';
    });
    try {
      final result = await processImage(
        source,
        ImageProcessingOptions(
          fit: _fit,
          dither: _dither,
          rotation: _rotation,
          threshold: _threshold.round(),
        ),
      );
      if (!mounted || generation != _processGeneration) return;
      setState(() {
        _processed = result;
        _phase = '图片已就绪';
      });
    } catch (error) {
      if (!mounted || generation != _processGeneration) return;
      _showError(_messageOf(error));
      setState(() => _phase = '图片处理失败');
    } finally {
      if (mounted && generation == _processGeneration) {
        setState(() => _processing = false);
      }
    }
  }

  Future<void> _openDeviceSwitcher() async {
    if (_scanning || _sending) return;
    final action = await showModalBottomSheet<_DeviceAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: _devices.length + 1,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            if (index == _devices.length) {
              return ListTile(
                leading: const Icon(Icons.add),
                title: const Text('添加设备'),
                onTap: () => Navigator.pop(
                  context,
                  const _DeviceAction(_DeviceActionType.add),
                ),
              );
            }
            final device = _devices[index];
            final selected = device.mac == _selectedDevice?.mac;
            return ListTile(
              leading: Icon(
                selected ? Icons.check_circle : Icons.developer_board_outlined,
              ),
              title: Text(device.name),
              subtitle: Text(device.mac),
              trailing: PopupMenuButton<_DeviceActionType>(
                tooltip: '管理设备',
                onSelected: (type) =>
                    Navigator.pop(context, _DeviceAction(type, device)),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _DeviceActionType.rename,
                    child: Text('修改设备名'),
                  ),
                  PopupMenuItem(
                    value: _DeviceActionType.unpair,
                    child: Text('解除配对'),
                  ),
                ],
              ),
              onTap: () => Navigator.pop(
                context,
                _DeviceAction(_DeviceActionType.select, device),
              ),
            );
          },
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action.type) {
      case _DeviceActionType.add:
        await _addDevice();
      case _DeviceActionType.select:
        await _selectDevice(action.device!);
      case _DeviceActionType.rename:
        await _renameDevice(action.device!);
      case _DeviceActionType.unpair:
        await _unpairDevice(action.device!);
    }
  }

  Future<void> _selectDevice(PairedDevice device) async {
    await _store.select(device.mac);
    if (!mounted) return;
    setState(() {
      _selectedDevice = device;
      _deviceOnline = false;
      _batteryLevel = null;
      _phase = '已选择 ${device.name}';
    });
    await _locateAndReadBattery();
  }

  Future<QuoteDevice?> _locate(String mac) async {
    setState(() => _scanning = true);
    try {
      return await _ble.findByMac(mac);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _locateAndReadBattery() async {
    final selected = _selectedDevice;
    if (selected == null) return;
    setState(() {
      _readingBattery = true;
      _phase = '正在查找 ${selected.name}';
    });
    try {
      final target = await _locate(selected.mac);
      if (!mounted || _selectedDevice?.mac != selected.mac) return;
      if (target == null) {
        setState(() {
          _deviceOnline = false;
          _batteryLevel = null;
          _phase = '${selected.name} 当前离线';
        });
        return;
      }
      final level = await _ble.readBattery(target);
      if (!mounted || _selectedDevice?.mac != selected.mac) return;
      setState(() {
        _deviceOnline = true;
        _batteryLevel = level;
        _phase = '${selected.name} 在线';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _deviceOnline = false;
          _batteryLevel = null;
          _phase = '${selected.name} 当前离线';
        });
      }
    } finally {
      if (mounted) setState(() => _readingBattery = false);
    }
  }

  Future<void> _addDevice() async {
    setState(() {
      _scanning = true;
      _phase = '正在查找设备';
    });
    try {
      final found = await _ble.scan();
      if (!mounted) return;
      if (found.isEmpty) {
        setState(() => _phase = '未找到 QuoteImage');
        return;
      }
      final chosen = await _chooseNearbyDevice(found);
      if (chosen == null || !mounted) return;
      final existing = _devices
          .where((item) => item.mac == chosen.mac)
          .firstOrNull;
      if (existing != null) {
        await _selectDevice(existing);
        return;
      }
      final info = await _ble.inspect(chosen);
      if (!info.pairingRequired) {
        final existingCredential = await _store.loadCredential(chosen.mac);
        if (existingCredential == null) {
          throw StateError('设备已配对，请由原手机解除配对或通过 USB 恢复');
        }
        final recoveredInfo = await _ble.recover(chosen, existingCredential);
        final recovered = PairedDevice(
          mac: recoveredInfo.mac,
          name: recoveredInfo.name,
          updatedAt: DateTime.now(),
        );
        await _store.upsert(recovered);
        await _store.select(recovered.mac);
        await _loadDevices();
        if (mounted) setState(() => _phase = '已恢复 ${recovered.name}');
        return;
      }
      while (mounted) {
        final code = await _promptPairCode(chosen.name);
        if (code == null) return;
        try {
          final pairedInfo = await _ble.pair(chosen, code, _store);
          final record = PairedDevice(
            mac: pairedInfo.mac,
            name: pairedInfo.name,
            updatedAt: DateTime.now(),
          );
          await _store.upsert(record);
          await _store.select(record.mac);
          if (!mounted) return;
          setState(() {
            _devices = [..._devices, record];
            _selectedDevice = record;
            _deviceOnline = true;
            _batteryLevel = null;
            _phase = '已配对 ${record.name}';
          });
          await _locateAndReadBattery();
          return;
        } on QuoteManagementException catch (error) {
          if (error.status != QuoteProtocol.managementInvalidCode &&
              error.status != QuoteProtocol.managementCodeRotated) {
            rethrow;
          }
          _showError(error.message);
        }
      }
    } catch (error) {
      if (mounted) {
        _showError(_messageOf(error));
        setState(() => _phase = '添加设备失败');
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<QuoteDevice?> _chooseNearbyDevice(List<QuoteDevice> devices) {
    return showModalBottomSheet<QuoteDevice>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: devices.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final device = devices[index];
            final paired = _devices.any((item) => item.mac == device.mac);
            return ListTile(
              leading: const Icon(Icons.developer_board_outlined),
              title: Text(device.name),
              subtitle: Text('${device.mac} · ${device.rssi} dBm'),
              trailing: paired
                  ? const Text('已配对')
                  : const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(context, device),
            );
          },
        ),
      ),
    );
  }

  Future<String?> _promptPairCode(String name) async {
    return showDialog<String>(
      context: context,
      builder: (context) => _PairCodeDialog(deviceName: name),
    );
  }

  Future<void> _renameDevice(PairedDevice record) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDeviceDialog(initialName: record.name),
    );
    if (name == null) return;
    try {
      final normalized = QuoteProtocol.normalizeDeviceName(name);
      final credential = await _store.loadCredential(record.mac);
      if (credential == null) {
        throw StateError('本机缺少设备凭证，请由原手机解除配对或通过 USB 恢复');
      }
      final target = await _locate(record.mac);
      if (target == null) throw StateError('${record.name} 当前离线');
      final info = await _ble.rename(target, credential, normalized);
      final updated = PairedDevice(
        mac: record.mac,
        name: info.name,
        updatedAt: DateTime.now(),
      );
      await _store.upsert(updated);
      if (!mounted) return;
      setState(() {
        _devices = [
          for (final device in _devices)
            if (device.mac == updated.mac) updated else device,
        ];
        if (_selectedDevice?.mac == updated.mac) _selectedDevice = updated;
        _phase = '设备已改名为 ${updated.name}';
      });
    } catch (error) {
      if (mounted) {
        if (error is QuoteManagementException &&
            error.status == QuoteProtocol.managementAuthRequired) {
          await _offerRemoveStaleRecord(record);
        } else {
          _showError(_messageOf(error));
        }
      }
    }
  }

  Future<void> _unpairDevice(PairedDevice record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('解除配对'),
        content: Text('解除与 ${record.name} 的配对？设备将显示新的配对码。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('解除配对'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final credential = await _store.loadCredential(record.mac);
      if (credential == null) throw StateError('本机缺少设备凭证，无法解除配对');
      final target = await _locate(record.mac);
      if (target == null) throw StateError('${record.name} 当前离线');
      await _ble.unpair(target, credential);
      await _store.deleteCredential(record.mac);
      await _store.remove(record.mac);
      await _loadDevices();
      if (mounted) setState(() => _phase = '已解除 ${record.name}');
    } catch (error) {
      if (mounted) {
        if (error is QuoteManagementException &&
            error.status == QuoteProtocol.managementAuthRequired) {
          await _offerRemoveStaleRecord(record);
        } else {
          _showError(_messageOf(error));
        }
      }
    }
  }

  Future<void> _offerRemoveStaleRecord(PairedDevice record) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设备需要重新配对'),
        content: Text('${record.name} 已恢复为未配对状态。清除本机的旧设备记录？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('保留'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除并重新添加'),
          ),
        ],
      ),
    );
    if (remove != true) return;
    await _store.deleteCredential(record.mac);
    await _store.remove(record.mac);
    await _loadDevices();
    if (mounted) await _addDevice();
  }

  Future<void> _send() async {
    final processed = _processed;
    if (processed == null) return;
    if (_selectedDevice == null) {
      await _openDeviceSwitcher();
      if (!mounted || _selectedDevice == null) return;
    }
    setState(() {
      _sending = true;
      _sendProgress = 0;
    });
    try {
      final selected = _selectedDevice!;
      final credential = await _store.loadCredential(selected.mac);
      if (credential == null) {
        throw StateError('本机缺少设备凭证，请由原手机解除配对或通过 USB 恢复');
      }
      final target = await _ble.findByMac(selected.mac);
      if (target == null) throw StateError('${selected.name} 当前离线');
      if (!mounted || _selectedDevice?.mac != selected.mac) return;
      setState(() {
        _deviceOnline = true;
      });
      await _ble.upload(
        target,
        credential,
        processed.frame,
        onProgress: (progress, phase) {
          if (!mounted) return;
          setState(() {
            _sendProgress = progress;
            _phase = phase;
          });
        },
        onBatteryLevel: (level) {
          if (mounted) setState(() => _batteryLevel = level);
        },
      );
    } catch (error) {
      if (mounted) {
        final selected = _selectedDevice;
        if (selected != null &&
            error is QuoteManagementException &&
            error.status == QuoteProtocol.managementAuthRequired) {
          await _offerRemoveStaleRecord(selected);
        } else {
          _showError(_messageOf(error));
          setState(() => _phase = '发送失败');
        }
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _messageOf(Object error) {
    if (error is StateError) return error.message;
    if (error is FormatException) return error.message;
    if (error is QuoteManagementException) return error.message;
    return error.toString().replaceFirst(RegExp(r'^Exception: '), '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QuoteWords'),
        actions: [
          IconButton(
            onPressed: _scanning ? null : _openDeviceSwitcher,
            tooltip: '切换设备',
            icon: _scanning
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.devices_other),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            final preview = _PreviewPane(
              processed: _processed,
              processing: _processing,
              onPick: _controlsEnabled ? _pickImage : null,
            );
            final controls = _buildControls();
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: preview),
                            const SizedBox(width: 36),
                            Expanded(child: controls),
                          ],
                        )
                      : Column(
                          children: [
                            preview,
                            const SizedBox(height: 28),
                            controls,
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusRow(
          deviceName: _selectedDevice?.name,
          online: _deviceOnline,
          batteryLevel: _batteryLevel,
          readingBattery: _readingBattery,
          scanning: _scanning,
          onSwitch: _scanning || _sending ? null : _openDeviceSwitcher,
        ),
        const SizedBox(height: 20),
        Text('尺寸适配', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<ImageFitMode>(
          segments: const [
            ButtonSegment(
              value: ImageFitMode.contain,
              label: Text('完整显示'),
              icon: Icon(Icons.fit_screen),
            ),
            ButtonSegment(
              value: ImageFitMode.cover,
              label: Text('裁切铺满'),
              icon: Icon(Icons.crop),
            ),
          ],
          selected: {_fit},
          onSelectionChanged: _controlsEnabled
              ? (selection) {
                  setState(() => _fit = selection.first);
                  _processImage();
                }
              : null,
        ),
        const SizedBox(height: 20),
        Text('旋转', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('0°')),
            ButtonSegment(value: 90, label: Text('90°')),
            ButtonSegment(value: 180, label: Text('180°')),
            ButtonSegment(value: 270, label: Text('270°')),
          ],
          selected: {_rotation},
          showSelectedIcon: false,
          onSelectionChanged: _controlsEnabled
              ? (selection) {
                  setState(() => _rotation = selection.first);
                  _processImage();
                }
              : null,
        ),
        const SizedBox(height: 20),
        Text('灰度处理', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<DitherMode>(
          segments: const [
            ButtonSegment(value: DitherMode.atkinson, label: Text('清晰灰阶')),
            ButtonSegment(value: DitherMode.threshold, label: Text('锐利黑白')),
          ],
          selected: {_dither},
          onSelectionChanged: _controlsEnabled
              ? (selection) {
                  setState(() => _dither = selection.first);
                  _processImage();
                }
              : null,
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Text('黑白阈值', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            Text(
              _threshold.round().toString(),
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        Slider(
          value: _threshold,
          min: 0,
          max: 255,
          divisions: 255,
          label: _threshold.round().toString(),
          onChanged: _controlsEnabled
              ? (value) => setState(() => _threshold = value)
              : null,
          onChangeEnd: _controlsEnabled ? (_) => _processImage() : null,
        ),
        const Divider(height: 32),
        Row(
          children: [
            Expanded(
              child: Text(
                _fileName ?? '未选择图片',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              onPressed: _controlsEnabled ? _pickImage : null,
              tooltip: '选择图片',
              icon: const Icon(Icons.photo_library_outlined),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_sending) ...[
          LinearProgressIndicator(value: _sendProgress),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                _phase,
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed:
                  _processed != null &&
                      !_processing &&
                      !_sending &&
                      !_readingBattery
                  ? _send
                  : null,
              icon: const Icon(Icons.send),
              label: const Text('发送到设备'),
            ),
          ],
        ),
      ],
    );
  }
}

class _PreviewPane extends StatelessWidget {
  const _PreviewPane({
    required this.processed,
    required this.processing,
    required this.onPick,
  });

  final ProcessedImage? processed;
  final bool processing;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 304),
            child: AspectRatio(
              aspectRatio: 296 / 152,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xff5d645d), width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x18000000),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (processed != null)
                      Image.memory(
                        processed!.previewPng,
                        fit: BoxFit.fill,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.none,
                      )
                    else
                      InkWell(
                        onTap: onPick,
                        child: const Center(
                          child: Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 42,
                            color: Color(0xff747b73),
                          ),
                        ),
                      ),
                    if (processing)
                      const ColoredBox(
                        color: Color(0x66ffffff),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '296 × 152',
          style: TextStyle(
            color: Color(0xff687068),
            fontSize: 12,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.deviceName,
    required this.online,
    required this.batteryLevel,
    required this.readingBattery,
    required this.scanning,
    required this.onSwitch,
  });

  final String? deviceName;
  final bool online;
  final int? batteryLevel;
  final bool readingBattery;
  final bool scanning;
  final VoidCallback? onSwitch;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          deviceName == null
              ? Icons.bluetooth_disabled
              : online
              ? Icons.bluetooth_connected
              : Icons.bluetooth,
          color: deviceName == null
              ? Theme.of(context).colorScheme.outline
              : online
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            deviceName ?? '未连接设备',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (deviceName != null) ...[
          Tooltip(
            message: '电池电量',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (readingBattery)
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    _batteryIcon(batteryLevel),
                    size: 20,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                const SizedBox(width: 4),
                Text(batteryLevel == null ? '--' : '$batteryLevel%'),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
        TextButton.icon(
          onPressed: onSwitch,
          icon: scanning
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.swap_horiz, size: 18),
          label: Text(scanning ? '查找中' : '切换'),
        ),
      ],
    );
  }

  IconData _batteryIcon(int? level) {
    if (level == null) return Icons.battery_unknown;
    if (level >= 85) return Icons.battery_full;
    if (level >= 60) return Icons.battery_5_bar;
    if (level >= 35) return Icons.battery_3_bar;
    if (level >= 15) return Icons.battery_2_bar;
    return Icons.battery_0_bar;
  }
}

class _PairCodeDialog extends StatefulWidget {
  const _PairCodeDialog({required this.deviceName});

  final String deviceName;

  @override
  State<_PairCodeDialog> createState() => _PairCodeDialogState();
}

class _PairCodeDialogState extends State<_PairCodeDialog> {
  String _code = '';

  void _submit() {
    if (_code.length == 4) Navigator.pop(context, _code);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('配对 ${widget.deviceName}'),
      content: TextField(
        autofocus: true,
        keyboardType: TextInputType.number,
        maxLength: 4,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
        decoration: const InputDecoration(labelText: '水墨屏上的 4 位配对码'),
        onChanged: (value) => setState(() => _code = value),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _code.length == 4 ? _submit : null,
          child: const Text('配对'),
        ),
      ],
    );
  }
}

class _RenameDeviceDialog extends StatefulWidget {
  const _RenameDeviceDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameDeviceDialog> createState() => _RenameDeviceDialogState();
}

class _RenameDeviceDialogState extends State<_RenameDeviceDialog> {
  late String _name = widget.initialName;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('修改设备名'),
      content: TextFormField(
        initialValue: widget.initialName,
        autofocus: true,
        maxLength: 24,
        decoration: const InputDecoration(labelText: '设备名'),
        onChanged: (value) => setState(() => _name = value),
        onFieldSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _name.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _name),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

enum _DeviceActionType { add, select, rename, unpair }

class _DeviceAction {
  const _DeviceAction(this.type, [this.device]);

  final _DeviceActionType type;
  final PairedDevice? device;
}
