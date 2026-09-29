/// Wire codec for the frozen SatoriEye BLE Control v1 contract.
class BleProtocol {
  static const serviceUuid = '4d89f6a0-73b9-4f14-9d3e-63b2145a0000';
  static const identityUuid = '4d89f6a0-73b9-4f14-9d3e-63b2145a0001';
  static const deviceInfoUuid = '4d89f6a0-73b9-4f14-9d3e-63b2145a0002';
  static const controlRxUuid = '4d89f6a0-73b9-4f14-9d3e-63b2145a0003';
  static const eventTxUuid = '4d89f6a0-73b9-4f14-9d3e-63b2145a0004';
  static const stateSnapshotUuid = '4d89f6a0-73b9-4f14-9d3e-63b2145a0005';
  static const version = 1;
  static const frameLength = 20;
  static const commandTimeout = Duration(milliseconds: 500);
  static const commandMaxRetries = 3;
  // Four attempts (2000 ms) plus 1000 ms link/scheduling margin, measured
  // by the device from completed RELEASE, never from request acceptance.
  static const releaseAckWindow = Duration(milliseconds: 3000);

  static List<int> encodeControlFrame({
    required BleOpcode opcode,
    required int sequence,
    required int token,
    List<int>? payload,
  }) {
    final p = payload ?? List<int>.filled(10, 0);
    if (sequence < 0 ||
        sequence > 0xffffffff ||
        token < 0 ||
        token > 0xffffffff ||
        p.length != 10 ||
        p.any((x) => x < 0 || x > 255)) {
      throw const FormatException('Invalid BLE control frame fields');
    }
    final b = List<int>.filled(20, 0);
    b[0] = version;
    b[1] = opcode.value;
    _put32(b, 2, sequence);
    _put32(b, 6, token);
    b.setRange(10, 20, p);
    return b;
  }

  static BleControlFrame decodeControlFrame(List<int> bytes) {
    if (bytes.length != 20) {
      throw const FormatException('Control frame must be 20 bytes');
    }
    return BleControlFrame(
      version: bytes[0],
      opcode: bytes[1],
      sequence: _u32(bytes, 2),
      token: _u32(bytes, 6),
      payload: List.unmodifiable(bytes.sublist(10)),
    );
  }

  static List<int> decodeIdentity(List<int> bytes) {
    _length(bytes, 16, 'DeviceIdentity');
    return List<int>.unmodifiable(bytes);
  }

  /// Applies the protocol's deterministic request checks for tooling/tests.
  /// ATT-level security and sequence-cache replay/conflict checks remain the
  /// transport peer's responsibility.
  static BleResult validateControlFrame(
    List<int> bytes, {
    required int currentToken,
    required bool armed,
    required bool subscribed,
    bool ownerAuthorized = true,
    bool supportsOwnerManagement = true,
    bool supportsSharedPairing = false,
    int currentPairingCode = 123456,
    bool transferWindowOpen = false,
    int maxTransitionMs = 2000,
  }) {
    if (bytes.length != 20) return BleResult.badLength;
    final f = decodeControlFrame(bytes);
    if (f.version != 1) return BleResult.badVersion;
    BleOpcode? op;
    for (final value in BleOpcode.values) {
      if (value.value == f.opcode) {
        op = value;
        break;
      }
    }
    if (op == null) return BleResult.badOpcode;
    if (f.sequence == 0) return BleResult.oldSequence;
    if (op == BleOpcode.claim) {
      if (!subscribed) return BleResult.subscriptionRequired;
      if (f.token != 0 || f.payload.any((x) => x != 0)) {
        return BleResult.badPayload;
      }
      return currentToken == 0 ? BleResult.ok : BleResult.badSession;
    }
    if (currentToken == 0 || f.token != currentToken) {
      return BleResult.badSession;
    }
    if (op == BleOpcode.setTarget) {
      final ch = [_u16(f.payload, 0), _u16(f.payload, 2), _u16(f.payload, 4)];
      if (ch.any((x) => x < 500 || x > 2500) ||
          _u16(f.payload, 6) > maxTransitionMs ||
          _u16(f.payload, 8) != 0) {
        return BleResult.badPayload;
      }
      return armed ? BleResult.ok : BleResult.notArmed;
    }
    if (op == BleOpcode.setPairingCode) {
      if (!supportsOwnerManagement) return BleResult.badOpcode;
      if (!ownerAuthorized) return BleResult.notAuthorized;
      final code = _u32(f.payload, 0);
      if (code > 999999 ||
          code == 123456 ||
          f.payload.sublist(4).any((x) => x != 0)) {
        return BleResult.badPayload;
      }
      if (transferWindowOpen) return BleResult.busy;
      return BleResult.ok;
    }
    if (op == BleOpcode.openTransfer || op == BleOpcode.cancelTransfer) {
      if (supportsSharedPairing) return BleResult.badOpcode;
      if (!ownerAuthorized) return BleResult.notAuthorized;
      if (f.payload.any((x) => x != 0)) return BleResult.badPayload;
      if (op == BleOpcode.openTransfer) {
        if (currentPairingCode == 123456) return BleResult.notConfigured;
        if (transferWindowOpen) return BleResult.busy;
      }
      return BleResult.ok;
    }
    if (f.payload.any((x) => x != 0)) return BleResult.badPayload;
    return BleResult.ok;
  }

  static List<int> encodeSetTarget({
    required int ch1,
    required int ch2,
    required int ch3,
    required int transitionMs,
  }) {
    final channels = [ch1, ch2, ch3];
    if (channels.any((x) => x < 500 || x > 2500) ||
        transitionMs < 0 ||
        transitionMs > 2000) {
      throw const FormatException('Invalid SET_TARGET range');
    }
    final p = List<int>.filled(10, 0);
    for (var i = 0; i < 3; i++) {
      _put16(p, i * 2, channels[i]);
    }
    _put16(p, 6, transitionMs);
    return p;
  }

  static List<int> encodePairingCode(String sixDigits) {
    if (!RegExp(r'^\d{6}$').hasMatch(sixDigits) || sixDigits == '123456') {
      throw const FormatException('Invalid pairing code');
    }
    final payload = List<int>.filled(10, 0);
    _put32(payload, 0, int.parse(sixDigits));
    return payload;
  }

  static BleDeviceInfo decodeDeviceInfo(List<int> b) {
    _length(b, 20, 'DeviceInfo');
    if (b[18] != 0 ||
        b[19] != 0 ||
        (_u32(b, 6) & ~0x1ff) != 0 ||
        (b[16] != 1 && b[16] != 2) ||
        b[17] != 3 ||
        b[10] == 0 ||
        b[11] == 0 ||
        b[10] > b[11] ||
        b[11] > 20 ||
        _u16(b, 12) == 0 ||
        _u16(b, 12) > 2000 ||
        _u16(b, 14) == 0 ||
        ((_u32(b, 6) & 0x100) != 0) != (b[16] == 2) ||
        (((_u32(b, 6) & 0x100) != 0) && b[1] < 2)) {
      throw const FormatException('Invalid DeviceInfo fields');
    }
    return BleDeviceInfo(
      protocolMajor: b[0],
      protocolMinor: b[1],
      firmwareMajor: b[2],
      firmwareMinor: b[3],
      firmwarePatch: b[4],
      hardwareProfile: b[5],
      capabilities: _u32(b, 6),
      recommendedTargetHz: b[10],
      maxTargetHz: b[11],
      maxTransitionMs: _u16(b, 12),
      leaseTimeoutMs: _u16(b, 14),
      securityPolicy: b[16],
      logicalChannels: b[17],
    );
  }

  static BleEvent decodeEvent(List<int> b) {
    _length(b, 20, 'Event');
    final result = BleResult.tryFromValue(b[10]);
    final sequence = _u32(b, 2);
    if (b[0] != 1 ||
        result == null ||
        (b[1] != 0xe0 && (b[1] < 0x81 || b[1] > 0x8a)) ||
        (b[1] == 0xe0 ? sequence != 0 : sequence == 0) ||
        b[11] > 3 ||
        (b[16] & 0xf0) != 0 ||
        (b[17] > 100 && b[17] != 255) ||
        b[18] != 0 ||
        b[19] != 0) {
      throw const FormatException('Invalid Event fields');
    }
    return BleEvent(
      version: b[0],
      opcode: b[1],
      sequence: _u32(b, 2),
      token: _u32(b, 6),
      result: result,
      controlState: b[11],
      lastAppliedSequence: _u32(b, 12),
      flags: b[16],
      batteryPercent: b[17] == 255 ? null : b[17],
    );
  }

  static BleStateSnapshot decodeStateSnapshot(List<int> b) {
    _length(b, 20, 'StateSnapshot');
    final channels = [_u16(b, 10), _u16(b, 12), _u16(b, 14)];
    if (b[0] != 1 ||
        b[1] > 3 ||
        (b[16] & 0xf8) != 0 ||
        (b[17] & 0xf8) != 0 ||
        (b[17] & ~b[16]) != 0 ||
        (b[18] > 100 && b[18] != 255) ||
        b[19] != 0 ||
        (b[1] == 0 && _u32(b, 2) != 0) ||
        (b[1] != 0 && _u32(b, 2) == 0)) {
      throw const FormatException('Invalid StateSnapshot fields');
    }
    for (var i = 0; i < 3; i++) {
      final valid = (b[16] & (1 << i)) != 0;
      if (valid
          ? (channels[i] < 500 || channels[i] > 2500)
          : channels[i] != 0) {
        throw const FormatException('Invalid StateSnapshot channel value');
      }
    }
    return BleStateSnapshot(
      version: b[0],
      controlState: b[1],
      token: _u32(b, 2),
      lastAppliedSequence: _u32(b, 6),
      channels: channels,
      validChannelMask: b[16],
      interpolatingChannelMask: b[17],
      batteryPercent: b[18] == 255 ? null : b[18],
    );
  }

  static List<int> encodeDeviceInfo({
    int protocolMinor = 0,
    int firmwareMajor = 0,
    int firmwareMinor = 0,
    int firmwarePatch = 0,
    int hardwareProfile = 1,
    int capabilities = 0x5f,
    int recommendedTargetHz = 20,
    int maxTargetHz = 20,
    int maxTransitionMs = 2000,
    int leaseTimeoutMs = 6000,
    int securityPolicy = 1,
    int logicalChannels = 3,
  }) {
    final b = List<int>.filled(20, 0);
    b[0] = 1;
    b[1] = protocolMinor;
    b[2] = firmwareMajor;
    b[3] = firmwareMinor;
    b[4] = firmwarePatch;
    b[5] = hardwareProfile;
    _put32(b, 6, capabilities);
    b[10] = recommendedTargetHz;
    b[11] = maxTargetHz;
    _put16(b, 12, maxTransitionMs);
    _put16(b, 14, leaseTimeoutMs);
    b[16] = securityPolicy;
    b[17] = logicalChannels;
    return b;
  }

  static List<int> encodeEvent({
    required int opcode,
    required int sequence,
    required int token,
    required BleResult result,
    int controlState = 1,
    int lastAppliedSequence = 0,
    int flags = 0,
    int? batteryPercent,
  }) {
    final b = List<int>.filled(20, 0);
    b[0] = 1;
    b[1] = opcode;
    _put32(b, 2, sequence);
    _put32(b, 6, token);
    b[10] = result.value;
    b[11] = controlState;
    _put32(b, 12, lastAppliedSequence);
    b[16] = flags;
    b[17] = batteryPercent ?? 255;
    return b;
  }

  static List<int> encodeStateSnapshot({
    int controlState = 0,
    int token = 0,
    int lastAppliedSequence = 0,
    List<int> channels = const [0, 0, 0],
    int validChannelMask = 0,
    int interpolatingChannelMask = 0,
    int? batteryPercent,
  }) {
    if (channels.length != 3) {
      throw const FormatException('Three state channels required');
    }
    final b = List<int>.filled(20, 0);
    b[0] = 1;
    b[1] = controlState;
    _put32(b, 2, token);
    _put32(b, 6, lastAppliedSequence);
    for (var i = 0; i < 3; i++) {
      _put16(b, 10 + 2 * i, channels[i]);
    }
    b[16] = validChannelMask;
    b[17] = interpolatingChannelMask;
    b[18] = batteryPercent ?? 255;
    return b;
  }

  static void _length(List<int> b, int n, String name) {
    if (b.length != n) throw FormatException('$name must be $n bytes');
    if (b.any((byte) => byte < 0 || byte > 255)) {
      throw FormatException('$name contains a non-byte value');
    }
  }

  static int _u16(List<int> b, int i) => b[i] | (b[i + 1] << 8);
  static int _u32(List<int> b, int i) =>
      b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24);
  static void _put16(List<int> b, int i, int v) {
    b[i] = v & 255;
    b[i + 1] = (v >> 8) & 255;
  }

  static void _put32(List<int> b, int i, int v) {
    for (var k = 0; k < 4; k++) {
      b[i + k] = (v >> (8 * k)) & 255;
    }
  }
}

enum BleOpcode {
  claim(1),
  setTarget(2),
  halt(3),
  release(4),
  keepalive(5),
  getStatus(6),
  arm(7),
  setPairingCode(8),
  openTransfer(9),
  cancelTransfer(10);

  const BleOpcode(this.value);
  final int value;
  int get replyValue => value | 0x80;
}

enum BleResult {
  ok(0),
  badVersion(1),
  badLength(2),
  badOpcode(3),
  badPayload(4),
  notAuthorized(5),
  badSession(6),
  oldSequence(7),
  sequenceConflict(8),
  busy(9),
  internalError(10),
  notArmed(11),
  notConfigured(12),
  subscriptionRequired(13);

  const BleResult(this.value);
  final int value;
  static BleResult? tryFromValue(int v) {
    for (final x in values) {
      if (x.value == v) return x;
    }
    return null;
  }

  static BleResult fromValue(int v) =>
      tryFromValue(v) ?? BleResult.internalError;
}

class BleControlFrame {
  const BleControlFrame({
    required this.version,
    required this.opcode,
    required this.sequence,
    required this.token,
    required this.payload,
  });
  final int version, opcode, sequence, token;
  final List<int> payload;
}

class BleDeviceInfo {
  const BleDeviceInfo({
    required this.protocolMajor,
    required this.protocolMinor,
    required this.firmwareMajor,
    required this.firmwareMinor,
    required this.firmwarePatch,
    required this.hardwareProfile,
    required this.capabilities,
    required this.recommendedTargetHz,
    required this.maxTargetHz,
    required this.maxTransitionMs,
    required this.leaseTimeoutMs,
    required this.securityPolicy,
    required this.logicalChannels,
  });
  final int protocolMajor,
      protocolMinor,
      firmwareMajor,
      firmwareMinor,
      firmwarePatch,
      hardwareProfile,
      capabilities,
      recommendedTargetHz,
      maxTargetHz,
      maxTransitionMs,
      leaseTimeoutMs,
      securityPolicy,
      logicalChannels;
  String get firmwareVersion => '$firmwareMajor.$firmwareMinor.$firmwarePatch';
  bool get supportsRequiredCapabilities => (capabilities & 0x5f) == 0x5f;
  bool get supportsOwnerManagement => (capabilities & 0x80) != 0;
  bool get supportsSharedPairing =>
      (capabilities & 0x100) != 0 && securityPolicy == 2;
}

class BleEvent {
  const BleEvent({
    required this.version,
    required this.opcode,
    required this.sequence,
    required this.token,
    required this.result,
    required this.controlState,
    required this.lastAppliedSequence,
    required this.flags,
    required this.batteryPercent,
  });
  final int version,
      opcode,
      sequence,
      token,
      controlState,
      lastAppliedSequence,
      flags;
  final BleResult result;
  final int? batteryPercent;
}

class BleStateSnapshot {
  const BleStateSnapshot({
    required this.version,
    required this.controlState,
    required this.token,
    required this.lastAppliedSequence,
    required this.channels,
    required this.validChannelMask,
    required this.interpolatingChannelMask,
    required this.batteryPercent,
  });
  final int version, controlState, token, lastAppliedSequence;
  final List<int> channels;
  final int validChannelMask, interpolatingChannelMask;
  final int? batteryPercent;
  bool get targetKnown => validChannelMask == 7;
}
