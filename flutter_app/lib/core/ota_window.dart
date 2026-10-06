/// Optional authenticated OTA extension; frozen Control v1.2 is unchanged.
class OtaWindowStatus {
  static const uuid = '4d89f6a0-73b9-4f14-9d3e-63b2145a0007';
  static const browserUrl = 'http://192.168.4.1/';
  const OtaWindowStatus(
    this.state,
    this.result,
    this.ackRequestId,
    this.windowId,
    this.remainingMs,
    this.ssid,
    this.password,
  );
  final int state, result, ackRequestId, windowId, remainingMs;
  final String ssid, password; // Ephemeral UI only; never log or persist.
  bool get isClosed => state == 0;
  bool get isOpen => state == 2 || state == 3;
  bool get isCommitted => state == 5;
  bool get signingReady => result != 2;
  factory OtaWindowStatus.decode(List<int> b) {
    if (b.length < 18 ||
        b.any((v) => v < 0 || v > 255) ||
        b[0] != 1 ||
        b[1] > 6 ||
        b[2] > 6 ||
        b[3] != 0 ||
        b[16] > 32 ||
        b[17] > 64 ||
        b.length != 18 + b[16] + b[17] ||
        b.sublist(18).any((v) => v < 32 || v > 126)) {
      throw const FormatException('Invalid OTA window status');
    }
    int u32(int i) => b[i] | b[i + 1] << 8 | b[i + 2] << 16 | b[i + 3] << 24;
    if ((b[1] == 2 || b[1] == 3) && (u32(8) == 0 || b[16] == 0 || b[17] < 8)) {
      throw const FormatException('OTA window connection data missing');
    }
    return OtaWindowStatus(
      b[1],
      b[2],
      u32(4),
      u32(8),
      u32(12),
      String.fromCharCodes(b.sublist(18, 18 + b[16])),
      String.fromCharCodes(b.sublist(18 + b[16])),
    );
  }
  Map<String, Object?> toUiJson() => {
    'state': state,
    'result': result,
    'ackRequestId': ackRequestId,
    'windowId': windowId,
    'remainingMs': remainingMs,
    'ssid': ssid,
    'password': password,
    'url': browserUrl,
  };
  static List<int> request({
    required bool open,
    required int requestId,
    required int windowId,
  }) {
    if (requestId <= 0 ||
        requestId > 0xffffffff ||
        windowId < 0 ||
        windowId > 0xffffffff ||
        (open ? windowId != 0 : windowId == 0)) {
      throw const FormatException('Invalid OTA window request');
    }
    final b = List<int>.filled(10, 0);
    b[0] = 1;
    b[1] = open ? 1 : 2;
    for (var i = 0; i < 4; i++) {
      b[2 + i] = (requestId >> (8 * i)) & 255;
      b[6 + i] = (windowId >> (8 * i)) & 255;
    }
    return b;
  }
}
