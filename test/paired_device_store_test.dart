import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quotewords/core/devices/paired_device_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  late SharedPreferencesAsync preferences;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    preferences = SharedPreferencesAsync();
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('device records persist separately from credentials', () async {
    final store = PersistentDeviceStore(preferences: preferences);
    final device = PairedDevice(
      mac: 'AA:BB:CC:DD:EE:FF',
      name: '书房',
      updatedAt: DateTime.utc(2026, 7, 23),
    );
    final credential = Uint8List.fromList(List.generate(16, (index) => index));

    await store.saveCredential(device.mac, credential);
    await store.upsert(device);
    await store.select(device.mac);

    expect(await store.loadDevices(), hasLength(1));
    expect((await store.loadDevices()).single.name, '书房');
    expect(await store.loadLastSelectedMac(), device.mac);
    expect(await store.loadCredential(device.mac), credential);

    expect(
      await preferences.getKeys(),
      isNot(contains('quoteimage.credential.v1.AABBCCDDEEFF')),
    );
    expect(
      await preferences.getString('quoteimage.devices.v1'),
      isNot(contains('AAECAw')),
    );
  });

  test(
    'removing the selected device clears selection but not implicitly credentials',
    () async {
      final store = PersistentDeviceStore(preferences: preferences);
      final device = PairedDevice(
        mac: 'AA:BB:CC:DD:EE:FF',
        name: 'Desk',
        updatedAt: DateTime.utc(2026),
      );
      await store.upsert(device);
      await store.select(device.mac);
      await store.saveCredential(device.mac, Uint8List(16));

      await store.remove(device.mac);

      expect(await store.loadDevices(), isEmpty);
      expect(await store.loadLastSelectedMac(), isNull);
      expect(await store.loadCredential(device.mac), isNotNull);
    },
  );
}
