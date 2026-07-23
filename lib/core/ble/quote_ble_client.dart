import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../devices/paired_device_store.dart';
import 'quote_protocol.dart';

class QuoteDevice {
  const QuoteDevice({
    required this.device,
    required this.name,
    required this.macBytes,
    required this.rssi,
  });

  final BluetoothDevice device;
  final String name;
  final Uint8List macBytes;
  final int rssi;

  String get mac => QuoteProtocol.formatMac(macBytes);
}

class QuoteBleClient {
  static final Guid _serviceGuid = Guid(QuoteProtocol.serviceUuid);

  Future<List<QuoteDevice>> scan({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!await FlutterBluePlus.isSupported) {
      throw StateError('此设备不支持 Bluetooth Low Energy');
    }
    final adapterState = await FlutterBluePlus.adapterState
        .where((state) => state != BluetoothAdapterState.unknown)
        .first;
    if (adapterState != BluetoothAdapterState.on) {
      throw StateError('请先打开蓝牙');
    }

    final found = <String, QuoteDevice>{};
    final subscription = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final advertisement = result.advertisementData;
        final hasService = advertisement.serviceUuids.contains(_serviceGuid);
        final identity =
            advertisement.manufacturerData[QuoteProtocol.manufacturerId];
        if (!hasService || identity == null || identity.length != 6) continue;
        final macBytes = Uint8List.fromList(identity);
        final mac = QuoteProtocol.formatMac(macBytes);
        found[mac] = QuoteDevice(
          device: result.device,
          name: advertisement.advName.isEmpty
              ? 'QuoteImage-${mac.replaceAll(':', '').substring(8)}'
              : advertisement.advName,
          macBytes: macBytes,
          rssi: result.rssi,
        );
      }
    });

    try {
      await FlutterBluePlus.startScan(
        withServices: [_serviceGuid],
        timeout: timeout,
      );
      await FlutterBluePlus.isScanning.where((scanning) => !scanning).first;
    } finally {
      await FlutterBluePlus.stopScan();
      await subscription.cancel();
    }
    final devices = found.values.toList()
      ..sort((left, right) => right.rssi.compareTo(left.rssi));
    return devices;
  }

  Future<QuoteDevice?> findByMac(
    String mac, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final normalized = QuoteProtocol.formatMac(QuoteProtocol.parseMac(mac));
    final devices = await scan(timeout: timeout);
    return devices.where((device) => device.mac == normalized).firstOrNull;
  }

  Future<QuoteDeviceInfo> pair(
    QuoteDevice target,
    String code,
    DeviceStore store,
  ) async {
    return _withConnection(target, (connection) async {
      final before = await connection.readAndValidateInfo();
      if (!before.pairingRequired) {
        throw const QuoteManagementException(
          QuoteProtocol.managementAlreadyPaired,
        );
      }
      final begin = await connection.exchangeManagement(
        QuoteProtocol.pairBeginPacket(code),
        QuoteProtocol.opPairBegin,
      );
      begin.requireSuccess();
      if (begin.payload.length != QuoteProtocol.credentialSize) {
        throw const FormatException('设备返回了无效的配对凭证');
      }
      final credential = Uint8List.fromList(begin.payload);
      var confirmSent = false;
      try {
        await store.saveCredential(target.mac, credential);
        confirmSent = true;
        final confirm = await connection.exchangeManagement(
          QuoteProtocol.pairConfirmPacket(credential),
          QuoteProtocol.opPairConfirm,
        );
        confirm.requireSuccess();
        final after = await connection.readAndValidateInfo();
        if (after.pairingRequired) {
          throw StateError('设备未完成配对');
        }
        return after;
      } catch (_) {
        if (!confirmSent) await store.deleteCredential(target.mac);
        rethrow;
      }
    });
  }

  Future<int> readBattery(QuoteDevice target) {
    return _withConnection(target, (connection) async {
      await connection.readAndValidateInfo();
      final level = await connection.readBattery();
      if (level == null) throw StateError('设备没有提供电池信息');
      return level;
    });
  }

  Future<QuoteDeviceInfo> inspect(QuoteDevice target) {
    return _withConnection(target, (connection) {
      return connection.readAndValidateInfo();
    });
  }

  Future<QuoteDeviceInfo> recover(QuoteDevice target, Uint8List credential) {
    return _withConnection(target, (connection) async {
      final info = await connection.readAndValidateInfo();
      if (info.pairingRequired) {
        throw const QuoteManagementException(
          QuoteProtocol.managementAuthRequired,
        );
      }
      await connection.authenticate(credential);
      return info;
    });
  }

  Future<QuoteDeviceInfo> rename(
    QuoteDevice target,
    Uint8List credential,
    String name,
  ) {
    return _withConnection(target, (connection) async {
      await connection.readAndValidateInfo();
      await connection.authenticate(credential);
      final response = await connection.exchangeManagement(
        QuoteProtocol.renamePacket(name),
        QuoteProtocol.opRename,
      );
      response.requireSuccess();
      return connection.readAndValidateInfo();
    });
  }

  Future<void> unpair(QuoteDevice target, Uint8List credential) {
    return _withConnection(target, (connection) async {
      await connection.readAndValidateInfo();
      await connection.authenticate(credential);
      final response = await connection.exchangeManagement(const [
        QuoteProtocol.opUnpair,
      ], QuoteProtocol.opUnpair);
      response.requireSuccess();
    });
  }

  Future<void> upload(
    QuoteDevice target,
    Uint8List credential,
    Uint8List frame, {
    required void Function(double progress, String phase) onProgress,
    void Function(int level)? onBatteryLevel,
  }) async {
    if (frame.length != QuoteProtocol.frameSize) {
      throw ArgumentError('帧必须为 ${QuoteProtocol.frameSize} 字节');
    }
    await _withConnection(target, (connection) async {
      onProgress(0, '正在连接');
      await connection.readAndValidateInfo();
      final batteryLevel = await connection.readBattery();
      if (batteryLevel != null) onBatteryLevel?.call(batteryLevel);
      await connection.authenticate(credential);

      final statusStream = StreamController<QuoteStatus>.broadcast(sync: true);
      QuoteStatus? latestStatus;
      final statusSubscription = connection.status.onValueReceived.listen((
        packet,
      ) {
        try {
          latestStatus = QuoteStatus.parse(packet);
          statusStream.add(latestStatus!);
        } catch (error, stackTrace) {
          statusStream.addError(error, stackTrace);
        }
      });
      try {
        await connection.status.setNotifyValue(true);

        Future<QuoteStatus> waitFor(Set<int> accepted, Duration timeout) async {
          final current = latestStatus;
          if (current != null) {
            if (current.isError) throw StateError(current.errorMessage);
            if (accepted.contains(current.code)) return current;
          }
          return statusStream.stream
              .firstWhere((value) {
                if (value.isError) throw StateError(value.errorMessage);
                return accepted.contains(value.code);
              })
              .timeout(timeout);
        }

        await connection.control.write(QuoteProtocol.startPacket(frame));
        await waitFor({
          QuoteProtocol.statusReceiving,
        }, const Duration(seconds: 5));

        final chunkSize = math.max(18, math.min(target.device.mtuNow - 5, 180));
        for (var offset = 0; offset < frame.length; offset += chunkSize) {
          final end = math.min(offset + chunkSize, frame.length);
          await connection.data.write(
            QuoteProtocol.dataPacket(offset, frame, end),
          );
          final current = latestStatus;
          if (current != null && current.isError) {
            throw StateError(current.errorMessage);
          }
          onProgress(end / frame.length * 0.8, '正在传输');
        }

        onProgress(0.82, '正在校验');
        await connection.control.write(const [QuoteProtocol.opCommit]);
        await waitFor({
          QuoteProtocol.statusReady,
          QuoteProtocol.statusRefreshing,
          QuoteProtocol.statusComplete,
        }, const Duration(seconds: 5));
        onProgress(0.9, '正在刷新屏幕');
        await waitFor({
          QuoteProtocol.statusComplete,
        }, const Duration(seconds: 45));
        onProgress(1, '刷新完成');
      } finally {
        await statusSubscription.cancel();
        await statusStream.close();
      }
    });
  }

  Future<T> _withConnection<T>(
    QuoteDevice target,
    Future<T> Function(_QuoteConnection connection) action,
  ) async {
    final connection = await _QuoteConnection.open(target);
    try {
      return await action(connection);
    } finally {
      await connection.close();
    }
  }
}

class _QuoteConnection {
  _QuoteConnection({
    required this.target,
    required this.control,
    required this.data,
    required this.status,
    required this.deviceInfo,
    required this.management,
    required this.batteryLevel,
  });

  final QuoteDevice target;
  final BluetoothCharacteristic control;
  final BluetoothCharacteristic data;
  final BluetoothCharacteristic status;
  final BluetoothCharacteristic deviceInfo;
  final BluetoothCharacteristic management;
  final BluetoothCharacteristic? batteryLevel;

  StreamSubscription<List<int>>? _managementSubscription;
  StreamController<QuoteManagementResponse>? _managementStream;

  static Future<_QuoteConnection> open(QuoteDevice target) async {
    final device = target.device;
    try {
      await device.connect(timeout: const Duration(seconds: 15), mtu: 247);
      final services = await device.discoverServices();
      final quoteService = services
          .where((service) => service.uuid == Guid(QuoteProtocol.serviceUuid))
          .firstOrNull;
      if (quoteService == null) {
        throw StateError('连接的设备不支持 QuoteImage 服务');
      }
      BluetoothCharacteristic? control;
      BluetoothCharacteristic? data;
      BluetoothCharacteristic? status;
      BluetoothCharacteristic? info;
      BluetoothCharacteristic? management;
      BluetoothCharacteristic? battery;
      for (final service in services) {
        for (final characteristic in service.characteristics) {
          final uuid = characteristic.uuid;
          if (uuid == Guid(QuoteProtocol.controlUuid)) control = characteristic;
          if (uuid == Guid(QuoteProtocol.dataUuid)) data = characteristic;
          if (uuid == Guid(QuoteProtocol.statusUuid)) status = characteristic;
          if (uuid == Guid(QuoteProtocol.deviceInfoUuid)) info = characteristic;
          if (uuid == Guid(QuoteProtocol.managementUuid)) {
            management = characteristic;
          }
          if (uuid == Guid(QuoteProtocol.batteryLevelUuid)) {
            battery = characteristic;
          }
        }
      }
      if (control == null ||
          data == null ||
          status == null ||
          info == null ||
          management == null) {
        throw StateError('QuoteImage GATT 特征不完整，请升级设备固件');
      }
      return _QuoteConnection(
        target: target,
        control: control,
        data: data,
        status: status,
        deviceInfo: info,
        management: management,
        batteryLevel: battery,
      );
    } catch (_) {
      if (device.isConnected) await device.disconnect();
      rethrow;
    }
  }

  Future<QuoteDeviceInfo> readAndValidateInfo() async {
    final info = QuoteDeviceInfo.parse(await deviceInfo.read());
    if (info.mac != target.mac) {
      throw StateError('广播身份与设备 MAC 不一致');
    }
    return info;
  }

  Future<int?> readBattery() async {
    final characteristic = batteryLevel;
    if (characteristic == null) return null;
    return QuoteProtocol.parseBatteryLevel(await characteristic.read());
  }

  Future<void> _enableManagementNotifications() async {
    if (_managementStream != null) return;
    final stream = StreamController<QuoteManagementResponse>.broadcast(
      sync: true,
    );
    _managementStream = stream;
    _managementSubscription = management.onValueReceived.listen((packet) {
      try {
        stream.add(QuoteManagementResponse.parse(packet));
      } catch (error, stackTrace) {
        stream.addError(error, stackTrace);
      }
    });
    await management.setNotifyValue(true);
  }

  Future<QuoteManagementResponse> exchangeManagement(
    List<int> packet,
    int expectedOpcode, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    await _enableManagementNotifications();
    final response = _managementStream!.stream
        .firstWhere((value) => value.opcode == expectedOpcode)
        .timeout(timeout);
    await management.write(packet);
    return response;
  }

  Future<void> authenticate(Uint8List credential) async {
    final challengeResponse = await exchangeManagement(const [
      QuoteProtocol.opAuthChallenge,
    ], QuoteProtocol.opAuthChallenge);
    challengeResponse.requireSuccess();
    if (challengeResponse.payload.length != 16) {
      throw const FormatException('设备返回了无效的认证 challenge');
    }
    final proof = QuoteProtocol.authenticationProof(
      credential,
      target.macBytes,
      challengeResponse.payload,
    );
    final proofResponse = await exchangeManagement([
      QuoteProtocol.opAuthProve,
      ...proof,
    ], QuoteProtocol.opAuthProve);
    proofResponse.requireSuccess();
  }

  Future<void> close() async {
    await _managementSubscription?.cancel();
    await _managementStream?.close();
    if (target.device.isConnected) await target.device.disconnect();
  }
}
