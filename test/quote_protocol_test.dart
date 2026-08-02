import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quotewords/core/ble/quote_protocol.dart';

void main() {
  test('CRC32 matches the standard check vector', () {
    expect(QuoteProtocol.crc32('123456789'.codeUnits), 0xcbf43926);
  });

  test('START packet contains protocol, size, and little-endian CRC', () {
    final frame = Uint8List(QuoteProtocol.frameSize);
    final packet = QuoteProtocol.startPacket(frame);

    expect(packet.length, 8);
    expect(packet[0], QuoteProtocol.opStart);
    expect(packet[1], QuoteProtocol.protocolVersion);
    expect(packet[2] | (packet[3] << 8), QuoteProtocol.frameSize);
    expect(packet.sublist(4), [0xfd, 0x59, 0xbf, 0xb4]);
  });

  test('data packets carry an offset and the selected frame range', () {
    final frame = Uint8List.fromList(List.generate(20, (index) => index));
    expect(QuoteProtocol.dataPacket(7, frame, 11), [7, 0, 7, 8, 9, 10]);
  });

  test('standard battery level must be a single percentage byte', () {
    expect(QuoteProtocol.parseBatteryLevel([73]), 73);
    expect(() => QuoteProtocol.parseBatteryLevel([]), throwsFormatException);
    expect(() => QuoteProtocol.parseBatteryLevel([101]), throwsFormatException);
  });

  test('device info exposes pairing state, MAC, and UTF-8 name', () {
    final packet = [
      QuoteProtocol.protocolVersion,
      1,
      0xaa,
      0xbb,
      0xcc,
      0xdd,
      0xee,
      0xff,
      ...'书房'.codeUnits.expand((unit) {
        if (unit < 0x80) return [unit];
        return <int>[];
      }),
    ];
    final asciiInfo = QuoteDeviceInfo.parse([
      ...packet.take(8),
      ...'Desk'.codeUnits,
    ]);
    expect(asciiInfo.mac, 'AA:BB:CC:DD:EE:FF');
    expect(asciiInfo.name, 'Desk');
    expect(asciiInfo.pairingRequired, isTrue);
  });

  test('MAC parsing and formatting are canonical', () {
    final bytes = QuoteProtocol.parseMac('aa:bb:cc:dd:ee:ff');
    expect(bytes, [0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff]);
    expect(QuoteProtocol.formatMac(bytes), 'AA:BB:CC:DD:EE:FF');
  });

  test('authentication proof matches firmware HMAC vector', () {
    final proof = QuoteProtocol.authenticationProof(
      List.generate(16, (index) => index),
      QuoteProtocol.parseMac('AA:BB:CC:DD:EE:FF'),
      List.generate(16, (index) => index + 16),
    );
    expect(
      proof.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
      '3aa76bea130ff386a42c1fa35725130d',
    );
  });

  test('management response preserves opcode, status, and payload', () {
    final response = QuoteManagementResponse.parse([
      1,
      3,
      0,
      ...List.filled(16, 7),
    ]);
    expect(response.opcode, QuoteProtocol.opAuthChallenge);
    expect(response.isSuccess, isTrue);
    expect(response.payload, hasLength(16));
  });
}
