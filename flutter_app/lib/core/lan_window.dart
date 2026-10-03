import 'dart:convert';
import 'ota_window.dart';

/// LAN extension status carries only a RAM token; never log this object.
class LanWindowStatus extends OtaWindowStatus {
  static const lanUuid = '4d89f6a0-73b9-4f14-9d3e-63b2145a0008';
  const LanWindowStatus(
    int state,
    int result,
    int ack,
    int window,
    int remaining,
    this.detail,
    this.ip,
    this.uploadToken,
  ) : super(state, result, ack, window, remaining, '', '');
  final int detail;
  final String ip, uploadToken;
  String get url => 'http://$ip/';
  factory LanWindowStatus.decode(List<int> b) {
    if (b.length < 24 ||
        b.any((v) => v < 0 || v > 255) ||
        b[0] != 1 ||
        b[1] > 6 ||
        b[2] > 6 ||
        b[3] > 4 ||
        (b[20] != 0 && b[20] != 32) ||
        b.length != 24 + b[20] ||
        b.sublist(21, 24).any((v) => v != 0)) {
      throw const FormatException('Invalid LAN maintenance status');
    }
    int u32(int n) => b[n] | b[n + 1] << 8 | b[n + 2] << 16 | b[n + 3] << 24;
    final open = b[1] == 2 || b[1] == 3;
    final token = String.fromCharCodes(b.sublist(24));
    final ipBytes = b.sublist(16, 20);
    if (open
        ? (u32(8) == 0 ||
              b[20] != 32 ||
              !RegExp(r'^[0-9a-f]{32}$').hasMatch(token) ||
              ipBytes[0] == 0 ||
              ipBytes[0] >= 224 ||
              ipBytes.every((v) => v == 255))
        : b[20] != 0) {
      throw const FormatException('Invalid LAN ready endpoint');
    }
    return LanWindowStatus(
      b[1],
      b[2],
      u32(4),
      u32(8),
      u32(12),
      b[3],
      ipBytes.join('.'),
      token,
    );
  }
  @override
  Map<String, Object?> toUiJson() => {
    'state': state, 'result': result, 'ackRequestId': ackRequestId,
    'windowId': windowId, 'remainingMs': remainingMs, 'detail': detail,
    'ip': isOpen ? ip : null, 'url': isOpen ? url : null,
    // Deliberately exclude uploadToken from public snapshots.
  };
  static List<int> lanRequest({
    required bool open,
    required int requestId,
    required int windowId,
    String ssid = '',
    String password = '',
  }) {
    final prefix = OtaWindowStatus.request(
      open: open,
      requestId: requestId,
      windowId: windowId,
    );
    final ssidBytes = utf8.encode(ssid), passwordBytes = password.codeUnits;
    if (open
        ? (ssidBytes.isEmpty ||
              ssidBytes.length > 32 ||
              ssidBytes.contains(0) ||
              passwordBytes.length < 8 ||
              passwordBytes.length > 63 ||
              passwordBytes.any((v) => v < 32 || v > 126))
        : (ssid.isNotEmpty || password.isNotEmpty)) {
      throw const FormatException(
        'Wi-Fi requires a 1–32 byte SSID and 8–63 ASCII password',
      );
    }
    return [
      ...prefix,
      ssidBytes.length,
      passwordBytes.length,
      ...ssidBytes,
      ...passwordBytes,
    ];
  }
}

/// Optional transport prerequisite for an atomic >20-byte BLE command.
abstract interface class BleLargeWriteLink {
  Future<void> prepareLargeWrite(int length);
}
