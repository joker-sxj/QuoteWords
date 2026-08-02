import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quoteimage_mobile/core/ble/quote_ble_client.dart';
import 'package:quoteimage_mobile/core/ble/quote_protocol.dart';
import 'package:quoteimage_mobile/core/devices/paired_device_store.dart';
import 'package:quoteimage_mobile/main.dart';

class MemoryDeviceStore implements DeviceStore {
  final List<PairedDevice> devices = [];
  final Map<String, Uint8List> credentials = {};
  String? selectedMac;

  @override
  Future<void> deleteCredential(String mac) async => credentials.remove(mac);

  @override
  Future<Uint8List?> loadCredential(String mac) async => credentials[mac];

  @override
  Future<List<PairedDevice>> loadDevices() async => List.of(devices);

  @override
  Future<String?> loadLastSelectedMac() async => selectedMac;

  @override
  Future<void> remove(String mac) async {
    devices.removeWhere((device) => device.mac == mac);
  }

  @override
  Future<void> saveCredential(String mac, Uint8List credential) async {
    credentials[mac] = credential;
  }

  @override
  Future<void> select(String? mac) async => selectedMac = mac;

  @override
  Future<void> upsert(PairedDevice device) async {
    devices.removeWhere((item) => item.mac == device.mac);
    devices.add(device);
  }
}

class OfflineBleClient extends QuoteBleClient {
  @override
  Future<QuoteDevice?> findByMac(
    String mac, {
    Duration timeout = const Duration(seconds: 5),
  }) async => null;
}

class PairingBleClient extends QuoteBleClient {
  PairingBleClient()
    : device = QuoteDevice(
        device: BluetoothDevice.fromId('pairing-test-device'),
        name: 'QuoteImage-EEFF',
        macBytes: QuoteProtocol.parseMac('AA:BB:CC:DD:EE:FF'),
        rssi: -42,
      );

  final QuoteDevice device;

  @override
  Future<List<QuoteDevice>> scan({
    Duration timeout = const Duration(seconds: 5),
  }) async => [device];

  @override
  Future<QuoteDeviceInfo> inspect(QuoteDevice target) async => QuoteDeviceInfo(
    macBytes: target.macBytes,
    name: target.name,
    pairingRequired: true,
  );

  @override
  Future<QuoteDeviceInfo> pair(
    QuoteDevice target,
    String code,
    DeviceStore store,
  ) async {
    await store.saveCredential(target.mac, Uint8List(16));
    return QuoteDeviceInfo(
      macBytes: target.macBytes,
      name: target.name,
      pairingRequired: false,
    );
  }

  @override
  Future<QuoteDevice?> findByMac(
    String mac, {
    Duration timeout = const Duration(seconds: 5),
  }) async => null;
}

void main() {
  testWidgets('editor exposes the complete image-to-device workflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      QuoteImageApp(
        deviceStore: MemoryDeviceStore(),
        initialSection: HomeSection.image,
      ),
    );
    await tester.pump();

    expect(find.text('QuoteImage'), findsOneWidget);
    expect(find.text('尺寸适配'), findsOneWidget);
    expect(find.text('Atkinson'), findsOneWidget);
    expect(find.text('296 × 152'), findsOneWidget);
    expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
    expect(find.text('发送到设备'), findsOneWidget);
    expect(find.text('切换'), findsOneWidget);
    final preview = tester.widget<AspectRatio>(find.byType(AspectRatio));
    expect(preview.aspectRatio, 296 / 152);
    final rotationControl = tester.widget<SegmentedButton<int>>(
      find.byWidgetPredicate(
        (widget) =>
            widget is SegmentedButton<int> && widget.segments.length == 4,
      ),
    );
    expect(rotationControl.selected, {0});
  });

  testWidgets('device switcher restores and changes the selected MAC offline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryDeviceStore()
      ..devices.addAll([
        PairedDevice(
          mac: 'AA:BB:CC:DD:EE:01',
          name: '书房',
          updatedAt: DateTime.utc(2026),
        ),
        PairedDevice(
          mac: 'AA:BB:CC:DD:EE:02',
          name: '卧室',
          updatedAt: DateTime.utc(2026),
        ),
      ])
      ..selectedMac = 'AA:BB:CC:DD:EE:01';

    await tester.pumpWidget(
      QuoteImageApp(
        deviceStore: store,
        bleClient: OfflineBleClient(),
        initialSection: HomeSection.image,
      ),
    );
    await tester.pump();
    expect(find.text('书房'), findsOneWidget);

    await tester.tap(find.text('切换'));
    await tester.pumpAndSettle();
    expect(find.text('卧室'), findsOneWidget);
    await tester.tap(find.text('卧室'));
    await tester.pumpAndSettle();

    expect(store.selectedMac, 'AA:BB:CC:DD:EE:02');
    expect(find.text('卧室'), findsOneWidget);
    expect(find.text('卧室 当前离线'), findsOneWidget);
  });

  testWidgets('pair-code confirmation closes without lifecycle assertions', (
    tester,
  ) async {
    final store = MemoryDeviceStore();
    await tester.pumpWidget(
      QuoteImageApp(
        deviceStore: store,
        bleClient: PairingBleClient(),
        initialSection: HomeSection.image,
      ),
    );
    await tester.pump();

    await tester.tap(find.text('切换'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加设备'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('QuoteImage-EEFF'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.enterText(find.byType(TextField), '0123');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '配对'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(store.devices.single.mac, 'AA:BB:CC:DD:EE:FF');
    expect(store.credentials, contains('AA:BB:CC:DD:EE:FF'));
  });
}
