import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

abstract final class QuoteProtocol {
  static const serviceUuid = '7a1e0000-6b4f-4e8b-a6d7-3e9b5c210000';
  static const controlUuid = '7a1e0001-6b4f-4e8b-a6d7-3e9b5c210000';
  static const dataUuid = '7a1e0002-6b4f-4e8b-a6d7-3e9b5c210000';
  static const statusUuid = '7a1e0003-6b4f-4e8b-a6d7-3e9b5c210000';
  static const deviceInfoUuid = '7a1e0004-6b4f-4e8b-a6d7-3e9b5c210000';
  static const managementUuid = '7a1e0005-6b4f-4e8b-a6d7-3e9b5c210000';
  static const batteryServiceUuid = '180f';
  static const batteryLevelUuid = '2a19';
  static const manufacturerId = 0xffff;

  static const protocolVersion = 1;
  static const frameWidth = 152;
  static const frameHeight = 296;
  static const frameSize = frameWidth * frameHeight ~/ 8;
  static const credentialSize = 16;

  static const opStart = 0x01;
  static const opCommit = 0x02;
  static const opAbort = 0x03;

  static const opPairBegin = 0x01;
  static const opPairConfirm = 0x02;
  static const opAuthChallenge = 0x03;
  static const opAuthProve = 0x04;
  static const opRename = 0x05;
  static const opUnpair = 0x06;

  static const managementOk = 0x00;
  static const managementInvalidRequest = 0x01;
  static const managementInvalidCode = 0x02;
  static const managementCodeRotated = 0x03;
  static const managementAlreadyPaired = 0x04;
  static const managementAuthFailed = 0x05;
  static const managementAuthRequired = 0x06;
  static const managementInvalidName = 0x07;
  static const managementStorageError = 0x08;
  static const managementBusy = 0x09;

  static const statusIdle = 0x00;
  static const statusReceiving = 0x01;
  static const statusReady = 0x02;
  static const statusRefreshing = 0x03;
  static const statusComplete = 0x04;
  static const errorInvalidCommand = 0x80;
  static const errorInvalidLength = 0x81;
  static const errorInvalidOffset = 0x82;
  static const errorCrcMismatch = 0x83;
  static const errorBusy = 0x84;
  static const errorDisplay = 0x85;
  static const errorUnauthorized = 0x86;

  static Uint8List startPacket(Uint8List frame) {
    if (frame.length != frameSize) {
      throw ArgumentError.value(frame.length, 'frame.length', 'must be 5624');
    }
    final data = ByteData(8)
      ..setUint8(0, opStart)
      ..setUint8(1, protocolVersion)
      ..setUint16(2, frame.length, Endian.little)
      ..setUint32(4, crc32(frame), Endian.little);
    return data.buffer.asUint8List();
  }

  static Uint8List dataPacket(int offset, Uint8List frame, int end) {
    final result = Uint8List(2 + end - offset);
    ByteData.sublistView(result).setUint16(0, offset, Endian.little);
    result.setRange(2, result.length, frame, offset);
    return result;
  }

  static Uint8List pairBeginPacket(String code) {
    if (!RegExp(r'^\d{4}$').hasMatch(code)) {
      throw const FormatException('配对码必须为 4 位数字');
    }
    return Uint8List.fromList([opPairBegin, ...ascii.encode(code)]);
  }

  static Uint8List pairConfirmPacket(List<int> credential) {
    _validateCredential(credential);
    return Uint8List.fromList([opPairConfirm, ...credential]);
  }

  static Uint8List renamePacket(String name) {
    final normalized = normalizeDeviceName(name);
    return Uint8List.fromList([opRename, ...utf8.encode(normalized)]);
  }

  static String normalizeDeviceName(String name) {
    final normalized = name.trim();
    final bytes = utf8.encode(normalized);
    if (bytes.isEmpty || bytes.length > 24) {
      throw const FormatException('设备名须为 1–24 个 UTF-8 字节');
    }
    if (normalized.runes.any((value) => value < 0x20 || value == 0x7f)) {
      throw const FormatException('设备名不能包含控制字符');
    }
    return normalized;
  }

  static Uint8List authenticationProof(
    List<int> credential,
    List<int> mac,
    List<int> challenge,
  ) {
    _validateCredential(credential);
    if (mac.length != 6 || challenge.length != 16) {
      throw const FormatException('认证参数长度无效');
    }
    final message = <int>[
      ...ascii.encode('QuoteImage-Auth-v1'),
      ...mac,
      ...challenge,
    ];
    final digest = Hmac(sha256, credential).convert(message).bytes;
    return Uint8List.fromList(digest.take(16).toList());
  }

  static int crc32(List<int> bytes) {
    var crc = 0xffffffff;
    for (final value in bytes) {
      crc ^= value;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc >>> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0);
      }
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }

  static int parseBatteryLevel(List<int> packet) {
    if (packet.length != 1 || packet.first > 100) {
      throw const FormatException('设备返回了无效的电池电量');
    }
    return packet.first;
  }

  static String formatMac(List<int> bytes) {
    if (bytes.length != 6) throw const FormatException('设备 MAC 长度无效');
    return bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
  }

  static Uint8List parseMac(String value) {
    final compact = value.replaceAll(':', '').toUpperCase();
    if (!RegExp(r'^[0-9A-F]{12}$').hasMatch(compact)) {
      throw const FormatException('设备 MAC 格式无效');
    }
    return Uint8List.fromList([
      for (var index = 0; index < compact.length; index += 2)
        int.parse(compact.substring(index, index + 2), radix: 16),
    ]);
  }

  static void _validateCredential(List<int> credential) {
    if (credential.length != credentialSize) {
      throw const FormatException('设备凭证长度无效');
    }
  }
}

class QuoteDeviceInfo {
  const QuoteDeviceInfo({
    required this.macBytes,
    required this.name,
    required this.pairingRequired,
  });

  final Uint8List macBytes;
  final String name;
  final bool pairingRequired;

  String get mac => QuoteProtocol.formatMac(macBytes);

  static QuoteDeviceInfo parse(List<int> packet) {
    if (packet.length < 9 || packet[0] != QuoteProtocol.protocolVersion) {
      throw const FormatException('设备返回了无效的设备信息');
    }
    final name = utf8.decode(packet.sublist(8), allowMalformed: false);
    return QuoteDeviceInfo(
      macBytes: Uint8List.fromList(packet.sublist(2, 8)),
      name: QuoteProtocol.normalizeDeviceName(name),
      pairingRequired: packet[1] & 0x01 != 0,
    );
  }
}

class QuoteManagementResponse {
  const QuoteManagementResponse(this.opcode, this.status, this.payload);

  final int opcode;
  final int status;
  final Uint8List payload;

  bool get isSuccess => status == QuoteProtocol.managementOk;

  static QuoteManagementResponse parse(List<int> packet) {
    if (packet.length < 3 || packet[0] != QuoteProtocol.protocolVersion) {
      throw const FormatException('设备返回了无效的管理响应');
    }
    return QuoteManagementResponse(
      packet[1],
      packet[2],
      Uint8List.fromList(packet.sublist(3)),
    );
  }

  void requireSuccess() {
    if (!isSuccess) throw QuoteManagementException(status);
  }
}

class QuoteManagementException implements Exception {
  const QuoteManagementException(this.status);

  final int status;

  String get message => switch (status) {
    QuoteProtocol.managementInvalidRequest => '设备拒绝了无效请求',
    QuoteProtocol.managementInvalidCode => '配对码不正确',
    QuoteProtocol.managementCodeRotated => '配对码已更换，请查看水墨屏',
    QuoteProtocol.managementAlreadyPaired => '设备已与另一台手机配对',
    QuoteProtocol.managementAuthFailed => '设备认证失败',
    QuoteProtocol.managementAuthRequired => '设备需要重新配对',
    QuoteProtocol.managementInvalidName => '设备名格式无效',
    QuoteProtocol.managementStorageError => '设备无法保存配置',
    QuoteProtocol.managementBusy => '设备正忙，请稍后重试',
    _ => '设备管理错误 (0x${status.toRadixString(16)})',
  };

  @override
  String toString() => message;
}

class QuoteStatus {
  const QuoteStatus(this.code, this.progress);

  final int code;
  final int progress;

  bool get isError => code >= 0x80;

  static QuoteStatus parse(List<int> packet) {
    if (packet.length != 4 || packet[0] != QuoteProtocol.protocolVersion) {
      throw const FormatException('设备返回了不兼容的状态包');
    }
    return QuoteStatus(packet[1], packet[2] | (packet[3] << 8));
  }

  String get errorMessage => switch (code) {
    QuoteProtocol.errorInvalidCommand => '设备拒绝了控制指令',
    QuoteProtocol.errorInvalidLength => '帧长度不正确',
    QuoteProtocol.errorInvalidOffset => '蓝牙分块顺序错误',
    QuoteProtocol.errorCrcMismatch => '帧 CRC 校验失败',
    QuoteProtocol.errorBusy => '设备正在处理另一帧',
    QuoteProtocol.errorDisplay => '墨水屏刷新失败',
    QuoteProtocol.errorUnauthorized => '设备未认证，请重新配对',
    _ => '设备错误 (0x${code.toRadixString(16)})',
  };
}
