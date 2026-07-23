import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ble/quote_protocol.dart';

class PairedDevice {
  const PairedDevice({
    required this.mac,
    required this.name,
    required this.updatedAt,
  });

  final String mac;
  final String name;
  final DateTime updatedAt;

  Map<String, Object> toJson() => {
    'mac': mac,
    'name': name,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static PairedDevice fromJson(Map<String, Object?> value) {
    final mac = QuoteProtocol.formatMac(
      QuoteProtocol.parseMac(value['mac']! as String),
    );
    final name = QuoteProtocol.normalizeDeviceName(value['name']! as String);
    return PairedDevice(
      mac: mac,
      name: name,
      updatedAt: DateTime.parse(value['updatedAt']! as String),
    );
  }
}

abstract interface class DeviceStore {
  Future<List<PairedDevice>> loadDevices();
  Future<String?> loadLastSelectedMac();
  Future<void> upsert(PairedDevice device);
  Future<void> remove(String mac);
  Future<void> select(String? mac);
  Future<Uint8List?> loadCredential(String mac);
  Future<void> saveCredential(String mac, Uint8List credential);
  Future<void> deleteCredential(String mac);
}

class PersistentDeviceStore implements DeviceStore {
  PersistentDeviceStore({
    SharedPreferencesAsync? preferences,
    FlutterSecureStorage? secureStorage,
  }) : _preferences = preferences ?? SharedPreferencesAsync(),
       _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _devicesKey = 'quoteimage.devices.v1';
  static const _selectedKey = 'quoteimage.selectedMac.v1';
  static const _credentialPrefix = 'quoteimage.credential.v1.';

  final SharedPreferencesAsync _preferences;
  final FlutterSecureStorage _secureStorage;

  @override
  Future<List<PairedDevice>> loadDevices() async {
    final encoded = await _preferences.getString(_devicesKey);
    if (encoded == null) return [];
    try {
      final values = jsonDecode(encoded) as List<dynamic>;
      final devices = values
          .map(
            (value) => PairedDevice.fromJson(
              Map<String, Object?>.from(value as Map<dynamic, dynamic>),
            ),
          )
          .toList();
      devices.sort((left, right) => left.name.compareTo(right.name));
      return devices;
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveDevices(List<PairedDevice> devices) {
    return _preferences.setString(
      _devicesKey,
      jsonEncode(devices.map((device) => device.toJson()).toList()),
    );
  }

  @override
  Future<String?> loadLastSelectedMac() => _preferences.getString(_selectedKey);

  @override
  Future<void> upsert(PairedDevice device) async {
    final devices = await loadDevices();
    devices.removeWhere((item) => item.mac == device.mac);
    devices.add(device);
    await _saveDevices(devices);
  }

  @override
  Future<void> remove(String mac) async {
    final devices = await loadDevices();
    devices.removeWhere((device) => device.mac == mac);
    await _saveDevices(devices);
    if (await loadLastSelectedMac() == mac) await select(null);
  }

  @override
  Future<void> select(String? mac) => mac == null
      ? _preferences.remove(_selectedKey)
      : _preferences.setString(_selectedKey, mac);

  @override
  Future<Uint8List?> loadCredential(String mac) async {
    final encoded = await _secureStorage.read(key: _credentialKey(mac));
    if (encoded == null) return null;
    try {
      final bytes = base64Decode(encoded);
      if (bytes.length != QuoteProtocol.credentialSize) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveCredential(String mac, Uint8List credential) async {
    if (credential.length != QuoteProtocol.credentialSize) {
      throw ArgumentError('credential must contain 16 bytes');
    }
    await _secureStorage.write(
      key: _credentialKey(mac),
      value: base64Encode(credential),
    );
  }

  @override
  Future<void> deleteCredential(String mac) {
    return _secureStorage.delete(key: _credentialKey(mac));
  }

  String _credentialKey(String mac) =>
      '$_credentialPrefix${mac.replaceAll(':', '').toUpperCase()}';
}
