import 'dart:async';
import 'dart:math';

import '../core/ble_protocol.dart';
import '../core/device_session.dart';

/// Shared persistent state for multiple synthetic phones talking to one
/// peripheral. It models passkey pairing and the single active control link.
class FakeBleSharedDevice {
  FakeBleSharedDevice({this.pairingCode = 123456, this.maxBonds = 8});

  int pairingCode;
  final int maxBonds;
  final Set<String> _bondedPhones = {};
  String? _activePhone;

  Set<String> get bondedPhones => Set.unmodifiable(_bondedPhones);
  String? get activePhone => _activePhone;

  bool pairPhone(String phoneId, String sixDigitCode) {
    if (_activePhone != null) return false;
    if (!RegExp(r'^\d{6}$').hasMatch(sixDigitCode) ||
        int.parse(sixDigitCode) != pairingCode) {
      return false;
    }
    if (_bondedPhones.contains(phoneId)) return true;
    if (_bondedPhones.length >= maxBonds) return false;
    _bondedPhones.add(phoneId);
    return true;
  }

  bool setPairingCode(String phoneId, int code) {
    if (_activePhone != phoneId ||
        !_bondedPhones.contains(phoneId) ||
        code < 0 ||
        code > 999999 ||
        code == 123456) {
      return false;
    }
    pairingCode = code;
    return true;
  }

  bool acquireControl(String phoneId) {
    if (!_bondedPhones.contains(phoneId) || _activePhone != null) return false;
    _activePhone = phoneId;
    return true;
  }

  void releaseControl(String phoneId) {
    if (_activePhone == phoneId) _activePhone = null;
  }
}

/// In-memory BLE peer with protocol sequencing, idempotency and a lease.
/// Its synthetic startup position is software test data, never calibration.
class FakeBleLink implements BleLink {
  FakeBleLink({
    this.identity = const [
      0,
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
      11,
      12,
      13,
      14,
      15,
    ],
    this.token = 0x12345678,
    this.dropNextReplies = 0,
    this.configured = true,
    this.writeDelay = Duration.zero,
    this.connectDelay = Duration.zero,
    this.subscriptionDelay = Duration.zero,
    this.leaseTimeout = const Duration(seconds: 6),
    this.snapshotTokenOverride,
    this.ownerAuthorized = true,
    this.ownerManagementSupported = true,
    this.nvsWriteFailures = 0,
    this.initialPairingCode = 123456,
    this.transferWindowTimeout = const Duration(seconds: 60),
    this.sharedPairingSupported = true,
    this.sharedDevice,
    this.phoneId = 'synthetic-phone',
  });
  final List<int> identity;
  final int token;
  final bool configured;
  final Duration leaseTimeout;
  Duration writeDelay;
  Duration connectDelay;
  Duration subscriptionDelay;
  int? snapshotTokenOverride;
  final bool ownerAuthorized;
  final bool ownerManagementSupported;
  int nvsWriteFailures;
  final int initialPairingCode;
  final Duration transferWindowTimeout;
  final bool sharedPairingSupported;
  final FakeBleSharedDevice? sharedDevice;
  final String phoneId;
  int? _pairingCode;
  bool _transferWindowOpen = false;
  Timer? _transferTimer;
  int get pairingCode =>
      sharedDevice?.pairingCode ?? _pairingCode ?? initialPairingCode;
  bool get transferWindowOpen => _transferWindowOpen;
  bool get ownerIdentityUnchanged => true;
  int pairingCodeWrites = 0;
  int dropNextReplies;
  final List<List<int>> writes = [];
  final List<List<int>> acceptedCommands = [];
  int acceptedTargetSubmissions = 0;
  final StreamController<BleLinkState> _states = StreamController.broadcast();
  final StreamController<List<int>> _events = StreamController.broadcast();
  BleLinkState _state = BleLinkState.disconnected;
  int _activeToken = 0, _highestSequence = 0, _lastApplied = 0;
  int _connectionCount = 0;
  final Map<int, List<int>> _requestCache = {};
  final Map<int, List<int>> _replyCache = {};
  bool _armed = false, _subscribed = false;
  bool _released = false;
  List<int> _channels = const [0, 0, 0];
  int _validMask = 0;
  Timer? _leaseTimer;
  Timer? _subscriptionTimer;
  Timer? _releaseTimer;
  Timer? _transferDisconnectTimer;
  bool _disposed = false;
  int _connectGeneration = 0;

  int get currentToken => _activeToken;
  int get highestSequence => _highestSequence;
  BleLinkState get currentState => _state;
  void revokeSession() {
    _leaseTimer?.cancel();
    _subscriptionTimer?.cancel();
    _releaseTimer?.cancel();
    _activeToken = 0;
    _released = true;
  }

  @override
  Stream<BleLinkState> get connectionState => _states.stream;

  @override
  Future<void> connect(String id) async {
    if (sharedDevice != null && !sharedDevice!.acquireControl(phoneId)) {
      throw StateError('Phone is unbonded or the control link is occupied');
    }
    final generation = ++_connectGeneration;
    _setState(BleLinkState.connecting);
    await Future<void>.delayed(connectDelay);
    if (generation != _connectGeneration) return;
    _setState(BleLinkState.connected);
    _connectionCount++;
    _activeToken = 0;
    _highestSequence = 0;
    _requestCache.clear();
    _replyCache.clear();
    _subscribed = false;
    _released = false;
    _leaseTimer?.cancel();
    _transferDisconnectTimer?.cancel();
  }

  @override
  Future<void> disconnect() async {
    _connectGeneration++;
    _leaseTimer?.cancel();
    _subscriptionTimer?.cancel();
    _releaseTimer?.cancel();
    _transferDisconnectTimer?.cancel();
    _activeToken = 0;
    _highestSequence = 0;
    _requestCache.clear();
    _replyCache.clear();
    _subscribed = false;
    _released = false;
    _setState(BleLinkState.disconnected);
    sharedDevice?.releaseControl(phoneId);
  }

  /// Models a device reboot: its persistent pairing code survives while the
  /// temporary transfer window and in-memory BLE session are cleared.
  Future<void> reboot() async {
    _transferTimer?.cancel();
    _transferDisconnectTimer?.cancel();
    _transferWindowOpen = false;
    await disconnect();
  }

  @override
  Future<List<int>> read(String uuid) async {
    if (_state != BleLinkState.connected) throw StateError('Not connected');
    if (uuid == BleProtocol.identityUuid) return List<int>.from(identity);
    if (uuid == BleProtocol.deviceInfoUuid) {
      return BleProtocol.encodeDeviceInfo(
        protocolMinor: sharedPairingSupported
            ? 2
            : (ownerManagementSupported ? 1 : 0),
        capabilities:
            (ownerManagementSupported ? 0xdf : 0x5f) |
            (sharedPairingSupported ? 0x100 : 0),
        securityPolicy: sharedPairingSupported ? 2 : 1,
      );
    }
    if (uuid == BleProtocol.stateSnapshotUuid) {
      return BleProtocol.encodeStateSnapshot(
        controlState: _activeToken == 0 ? 0 : 1,
        token: _activeToken == 0
            ? _activeToken
            : (snapshotTokenOverride ?? _activeToken),
        lastAppliedSequence: _lastApplied,
        channels: _channels,
        validChannelMask: _validMask,
      );
    }
    throw StateError('Unknown characteristic $uuid');
  }

  @override
  Stream<List<int>> subscribe(String uuid) {
    if (uuid != BleProtocol.eventTxUuid) {
      throw StateError('Unknown notify characteristic');
    }
    _subscriptionTimer?.cancel();
    if (subscriptionDelay == Duration.zero) {
      _subscribed = true;
    } else {
      _subscribed = false;
      _subscriptionTimer = Timer(subscriptionDelay, () {
        if (_state == BleLinkState.connected) _subscribed = true;
      });
    }
    return _events.stream;
  }

  @override
  Future<void> write(String uuid, List<int> value) async {
    if (uuid != BleProtocol.controlRxUuid || _state != BleLinkState.connected) {
      throw StateError('Invalid write');
    }
    if (writeDelay > Duration.zero) await Future<void>.delayed(writeDelay);
    final bytes = List<int>.from(value);
    writes.add(bytes);
    if (bytes.length != 20) {
      return; // BLE ATT would reject malformed value lengths.
    }
    final frame = BleProtocol.decodeControlFrame(bytes);
    final oldRequest = _requestCache[frame.sequence];
    if (oldRequest != null) {
      if (_same(oldRequest, bytes)) {
        final cached = _replyCache[frame.sequence];
        if (cached != null && _subscribed) {
          if (dropNextReplies > 0) {
            dropNextReplies--;
            return;
          }
          _events.add(List<int>.from(cached));
        }
      } else {
        _reply(frame, BleResult.sequenceConflict);
      }
      return;
    }
    if (frame.opcode == BleOpcode.claim.value && _released) {
      _reply(frame, BleResult.badSession);
      return;
    }
    if (_released && frame.opcode != BleOpcode.release.value) {
      _reply(frame, BleResult.badSession);
      return;
    }
    if (frame.sequence <= _highestSequence && frame.sequence != 0) {
      _reply(frame, BleResult.oldSequence);
      return;
    }

    final result = BleProtocol.validateControlFrame(
      bytes,
      currentToken: _activeToken,
      armed: _armed,
      subscribed: _subscribed,
      ownerAuthorized: ownerAuthorized,
      supportsOwnerManagement: ownerManagementSupported,
      supportsSharedPairing: sharedPairingSupported,
      currentPairingCode: pairingCode,
      transferWindowOpen: _transferWindowOpen,
    );
    if (result != BleResult.ok) {
      _reply(frame, result);
      return;
    }
    if (frame.opcode == BleOpcode.setPairingCode.value &&
        nvsWriteFailures > 0) {
      nvsWriteFailures--;
      _reply(frame, BleResult.internalError);
      return;
    }
    var responseToken = frame.token;
    switch (frame.opcode) {
      case 1:
        _activeToken = token == 0
            ? Random().nextInt(0xffffffff) + 1
            : (token + _connectionCount - 1) & 0xffffffff;
        if (_activeToken == 0) _activeToken = 1;
        responseToken = _activeToken;
        _touchLease();
        break;
      case 7:
        if (_validMask != 7) {
          if (!configured) {
            _reply(frame, BleResult.notConfigured);
            return;
          }
          _channels = const [1500, 1500, 1500];
          _validMask = 7;
        }
        _armed = true;
        _lastApplied = frame.sequence;
        _touchLease();
        break;
      case 8:
        _pairingCode =
            frame.payload[0] |
            (frame.payload[1] << 8) |
            (frame.payload[2] << 16) |
            (frame.payload[3] << 24);
        sharedDevice?.setPairingCode(phoneId, _pairingCode!);
        pairingCodeWrites++;
        _touchLease();
        break;
      case 9:
        _lastApplied = frame.sequence;
        _armed = false;
        _touchLease();
        _transferWindowOpen = true;
        _transferTimer?.cancel();
        _transferTimer = Timer(transferWindowTimeout, () {
          _transferWindowOpen = false;
        });
        _transferDisconnectTimer?.cancel();
        _transferDisconnectTimer = Timer(
          const Duration(milliseconds: 400),
          disconnect,
        );
        break;
      case 10:
        _transferWindowOpen = false;
        _transferTimer?.cancel();
        _transferDisconnectTimer?.cancel();
        _touchLease();
        break;
      case 2:
        _channels = [
          _u16(frame.payload, 0),
          _u16(frame.payload, 2),
          _u16(frame.payload, 4),
        ];
        _validMask = 7;
        _lastApplied = frame.sequence;
        acceptedTargetSubmissions++;
        _touchLease();
        break;
      case 3:
        _lastApplied = frame.sequence;
        _touchLease();
        break;
      case 4:
        _lastApplied = frame.sequence;
        _leaseTimer?.cancel();
        _activeToken = 0;
        _armed = _validMask == 7;
        _released = true;
        responseToken = frame.token;
        _releaseTimer?.cancel();
        _releaseTimer = Timer(const Duration(milliseconds: 500), disconnect);
        break;
      case 5:
        _touchLease();
        break;
      case 6:
        // Status reads and GET_STATUS are deliberately not lease activity.
        break;
      default:
        _reply(frame, BleResult.badOpcode);
        return;
    }
    _highestSequence = frame.sequence;
    acceptedCommands.add(bytes);
    final ack = _makeReply(frame, result, responseToken);
    if (frame.opcode == 4) {
      _requestCache.clear();
      _replyCache.clear();
    }
    _cache(frame.sequence, bytes, ack);
    if (dropNextReplies > 0) {
      dropNextReplies--;
      return;
    }
    if (_subscribed) _events.add(ack);
  }

  void _reply(BleControlFrame frame, BleResult result) {
    if (!_subscribed) return;
    _events.add(
      _makeReply(
        frame,
        result,
        frame.opcode == BleOpcode.claim.value && result == BleResult.ok
            ? _activeToken
            : frame.token,
      ),
    );
  }

  List<int> _makeReply(
    BleControlFrame frame,
    BleResult result,
    int responseToken,
  ) => BleProtocol.encodeEvent(
    opcode: frame.opcode | 0x80,
    sequence: frame.sequence,
    token: responseToken,
    result: result,
    controlState: _activeToken == 0 ? 0 : 1,
    lastAppliedSequence: _lastApplied,
    flags: (_validMask == 7 ? 1 : 0) | (_activeToken != 0 ? 8 : 0),
  );
  void _cache(int sequence, List<int> request, List<int> reply) {
    _requestCache[sequence] = List<int>.from(request);
    _replyCache[sequence] = List<int>.from(reply);
    while (_requestCache.length > 16) {
      final oldest = _requestCache.keys.first;
      _requestCache.remove(oldest);
      _replyCache.remove(oldest);
    }
  }

  void _touchLease() {
    _leaseTimer?.cancel();
    _leaseTimer = Timer(leaseTimeout, _expireLease);
  }

  void _expireLease() {
    _leaseTimer?.cancel();
    _subscriptionTimer?.cancel();
    _releaseTimer?.cancel();
    _transferDisconnectTimer?.cancel();
    _activeToken = 0;
    _armed = _validMask == 7;
    _requestCache.clear();
    _replyCache.clear();
    _highestSequence = 0;
    _subscribed = false;
    sharedDevice?.releaseControl(phoneId);
    _setState(BleLinkState.disconnected);
  }

  void expireLeaseNow() => _expireLease();
  void emitEvent(List<int> event) {
    if (_subscribed) _events.add(List<int>.from(event));
  }

  void failNotifications(Object error) {
    if (_subscribed) _events.addError(error);
  }

  void _setState(BleLinkState next) {
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  static int _u16(List<int> b, int i) => b[i] | b[i + 1] << 8;
  bool _same(List<int> a, List<int> b) =>
      a.length == b.length &&
      List.generate(a.length, (i) => a[i] == b[i]).every((x) => x);
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _leaseTimer?.cancel();
    _subscriptionTimer?.cancel();
    _releaseTimer?.cancel();
    _transferTimer?.cancel();
    _transferDisconnectTimer?.cancel();
    await _states.close();
    await _events.close();
  }
}
