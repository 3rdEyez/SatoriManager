import 'dart:async';

import 'ble_protocol.dart';

enum BleLinkState { disconnected, connecting, connected }

/// Small transport contract. Scanning, pairing and platform GATT setup live in
/// the concrete adapter; this class owns the protocol and its single writer.
abstract class BleLink {
  Stream<BleLinkState> get connectionState;
  Future<void> connect(String id);
  Future<void> disconnect();
  Future<List<int>> read(String uuid);
  Future<void> write(String uuid, List<int> value);
  Stream<List<int>> subscribe(String uuid);
}

enum DeviceSessionPhase {
  disconnected,
  connecting,
  reading,
  claiming,
  readyPaused,
  armed,
  error,
}

class DeviceSessionSnapshot {
  const DeviceSessionSnapshot({
    required this.phase,
    this.identity,
    this.deviceInfo,
    this.state,
    this.token = 0,
    this.sequence = 0,
    this.lastAckSequence,
    this.lastAckAt,
    this.lastError,
  });
  final DeviceSessionPhase phase;
  final String? identity;
  final BleDeviceInfo? deviceInfo;
  final BleStateSnapshot? state;
  final int token, sequence;
  final int? lastAckSequence;
  final DateTime? lastAckAt;
  final String? lastError;
  bool get isConnected =>
      phase == DeviceSessionPhase.readyPaused ||
      phase == DeviceSessionPhase.armed;
  bool get isArmed => phase == DeviceSessionPhase.armed;
  bool get targetKnown => isArmed && (state?.targetKnown ?? false);
}

class TargetCancelledException implements Exception {
  const TargetCancelledException([
    this.reason = 'Target was cancelled before transmission',
  ]);
  final String reason;
  @override
  String toString() => reason;
}

class BleCommandRejected implements Exception {
  const BleCommandRejected(this.opcode, this.result);
  final BleOpcode opcode;
  final BleResult result;
  @override
  String toString() => 'BLE command ${opcode.name} rejected: ${result.name}';
}

class DeviceSession {
  DeviceSession(
    this.link, {
    this.expectedDeviceIdentity,
    this.commandTimeout = BleProtocol.commandTimeout,
    this.maxRetries = BleProtocol.commandMaxRetries,
  }) : _postClaimSequenceForTesting = null {
    _listenLink();
  }

  /// Sequence seed seam for deterministic boundary tests; CLAIM still starts
  /// at sequence one as required by the protocol.
  DeviceSession.testSeeded(
    this.link, {
    required int nextSequence,
    this.expectedDeviceIdentity,
    this.commandTimeout = BleProtocol.commandTimeout,
    this.maxRetries = BleProtocol.commandMaxRetries,
  }) : _postClaimSequenceForTesting = nextSequence {
    if (nextSequence < 2 || nextSequence > 0xffffffff) {
      throw ArgumentError.value(nextSequence, 'nextSequence');
    }
    _listenLink();
  }

  void _listenLink() {
    _linkSub = link.connectionState.listen((state) {
      if (state == BleLinkState.disconnected &&
          _snapshot.phase != DeviceSessionPhase.disconnected) {
        _invalidate('BLE disconnected');
      }
    });
  }

  final BleLink link;
  final String? expectedDeviceIdentity;
  final Duration commandTimeout;
  final int maxRetries;
  final int? _postClaimSequenceForTesting;
  final _updates = StreamController<DeviceSessionSnapshot>.broadcast();
  StreamSubscription<BleLinkState>? _linkSub;
  StreamSubscription<List<int>>? _eventSub;
  Timer? _keepalive;
  DeviceSessionSnapshot _snapshot = const DeviceSessionSnapshot(
    phase: DeviceSessionPhase.disconnected,
  );
  DeviceSessionSnapshot get snapshot => _snapshot;
  Stream<DeviceSessionSnapshot> get snapshots => _updates.stream;
  int _generation = 0, _token = 0, _nextSequence = 1;
  final Stopwatch _monotonic = Stopwatch()..start();
  Future<void> _writeTail = Future<void>.value();
  final Map<int, Completer<BleEvent>> _pending = {};
  final Map<int, int> _pendingTokens = {};
  List<int>? _latestTarget;
  Completer<void>? _latestTargetDone;
  bool _targetPumpScheduled = false, _disposed = false;
  int _targetGeneration = 0;
  Duration? _lastTargetSentAt;
  Timer? _stateRefresh;
  bool _stateReadInProgress = false;
  bool _releaseInProgress = false;

  void _emit(DeviceSessionSnapshot next) {
    if (_disposed) return;
    _snapshot = next;
    if (!_updates.isClosed) _updates.add(next);
  }

  DeviceSessionSnapshot _copy({
    DeviceSessionPhase? phase,
    String? identity,
    BleDeviceInfo? deviceInfo,
    BleStateSnapshot? state,
    int? token,
    int? sequence,
    int? lastAckSequence,
    DateTime? lastAckAt,
    String? lastError,
  }) => DeviceSessionSnapshot(
    phase: phase ?? _snapshot.phase,
    identity: identity ?? _snapshot.identity,
    deviceInfo: deviceInfo ?? _snapshot.deviceInfo,
    state: state ?? _snapshot.state,
    token: token ?? _snapshot.token,
    sequence: sequence ?? _snapshot.sequence,
    lastAckSequence: lastAckSequence ?? _snapshot.lastAckSequence,
    lastAckAt: lastAckAt ?? _snapshot.lastAckAt,
    lastError: lastError,
  );

  Future<void> connect(String id, {String? expectedIdentity}) async {
    final generation = ++_generation;
    _clearPending();
    _token = 0;
    _nextSequence = 1;
    _emit(const DeviceSessionSnapshot(phase: DeviceSessionPhase.connecting));
    try {
      await link.connect(id);
      _checkGeneration(generation);
      _emit(_copy(phase: DeviceSessionPhase.reading));
      final identityBytes = await _setupRead(BleProtocol.identityUuid);
      _checkGeneration(generation);
      if (identityBytes.length != 16) {
        throw const FormatException('DeviceIdentity must be 16 bytes');
      }
      final identity = identityBytes
          .map((x) => x.toRadixString(16).padLeft(2, '0'))
          .join();
      final expected = expectedIdentity ?? expectedDeviceIdentity;
      if (expected != null &&
          identity.toLowerCase() !=
              expected.replaceAll('-', '').toLowerCase()) {
        throw StateError('Device identity mismatch');
      }
      final info = BleProtocol.decodeDeviceInfo(
        await _setupRead(BleProtocol.deviceInfoUuid),
      );
      _checkGeneration(generation);
      if (info.protocolMajor != 1 || !info.supportsRequiredCapabilities) {
        throw StateError(
          'Incompatible BLE protocol or missing required capabilities',
        );
      }
      // The plugin exposes no CCCD-ready future. The protected read triggers
      // pairing, then identity is re-read through the authenticated link.
      final securedState = BleProtocol.decodeStateSnapshot(
        await _setupRead(BleProtocol.stateSnapshotUuid, securitySetup: true),
      );
      _checkGeneration(generation);
      if (securedState.version != 1) {
        throw StateError('Unsupported StateSnapshot version');
      }
      final verifiedIdentity = await _setupRead(BleProtocol.identityUuid);
      _checkGeneration(generation);
      if (!_sameBytes(identityBytes, verifiedIdentity)) {
        throw StateError('Device identity changed during secure setup');
      }
      await _eventSub?.cancel();
      // The BLE plugin has no CCCD-ready future. Listening starts the native
      // subscription; if setup still races CLAIM, only its same-byte seq=1
      // retry path is allowed to recover the missing subscription.
      _eventSub = link
          .subscribe(BleProtocol.eventTxUuid)
          .listen(
            _onEvent,
            onError: (Object e) => _notificationFailure(e),
            onDone: _notificationEnded,
          );
      _emit(_copy(identity: identity, deviceInfo: info));
      _emit(_copy(phase: DeviceSessionPhase.claiming));
      final claim = await _command(
        BleOpcode.claim,
        token: 0,
        generation: generation,
      );
      _checkGeneration(generation);
      _token = claim.token;
      if (_token == 0) throw StateError('CLAIM returned a zero token');
      _nextSequence = _postClaimSequenceForTesting ?? 2;
      final state = await _readSnapshot(generation);
      _checkGeneration(generation);
      if (state.version != 1 || state.token != _token) {
        throw StateError('StateSnapshot token/version does not match CLAIM');
      }
      _emit(
        _copy(
          phase: DeviceSessionPhase.readyPaused,
          state: state,
          token: _token,
          sequence: 1,
          lastAckSequence: 1,
          lastAckAt: DateTime.now(),
        ),
      );
      _keepalive?.cancel();
      _keepalive = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _enqueueCommand(BleOpcode.keepalive).catchError((Object e) {
          _fail(e);
          if (e is BleCommandRejected && _fatalResult(e.result)) {
            unawaited(link.disconnect());
          }
        }),
      );
      _stateRefresh?.cancel();
      _stateRefresh = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => _refreshState(),
      );
    } catch (e) {
      if (generation == _generation) {
        await _eventSub?.cancel();
        _eventSub = null;
        _token = 0;
        try {
          await link.disconnect();
        } catch (_) {}
        _emit(_copy(phase: DeviceSessionPhase.error, lastError: e.toString()));
      }
      rethrow;
    }
  }

  Future<List<int>> _setupRead(String uuid, {bool securitySetup = false}) =>
      link
          .read(uuid)
          .timeout(
            securitySetup
                ? const Duration(seconds: 90)
                : const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException('Timed out reading $uuid'),
          );
  Future<BleStateSnapshot> _readSnapshot(int generation) async {
    final state = BleProtocol.decodeStateSnapshot(
      await link
          .read(BleProtocol.stateSnapshotUuid)
          .timeout(const Duration(seconds: 2)),
    );
    _checkGeneration(generation);
    return state;
  }

  bool _sameBytes(List<int> a, List<int> b) =>
      a.length == b.length &&
      List.generate(a.length, (i) => a[i] == b[i]).every((v) => v);

  Future<void> arm({void Function()? beforeSend}) async {
    _ensureReady();
    final generation = _generation;
    await _enqueueCommand(BleOpcode.arm, beforeSend: beforeSend);
    _checkGeneration(generation);
    if (!_snapshot.targetKnown) {
      throw StateError('ARM succeeded without a known three-channel output');
    }
  }

  /// Changes the persistent owner pairing code. The value is never copied to
  /// a session snapshot or included in errors; only the encoded frame carries
  /// it over the encrypted BLE link.
  Future<void> setPairingCode(
    String sixDigits, {
    void Function()? beforeSend,
  }) async {
    _ensureOwnerManagement();
    final payload = BleProtocol.encodePairingCode(sixDigits);
    final generation = _generation;
    await _enqueueCommand(
      BleOpcode.setPairingCode,
      payload: payload,
      beforeSend: beforeSend,
    );
    _checkGeneration(generation);
  }

  Future<void> openTransfer({void Function()? beforeSend}) async {
    _ensureOwnerManagement();
    final generation = _generation;
    await _enqueueCommand(BleOpcode.openTransfer, beforeSend: beforeSend);
    _checkGeneration(generation);
    // OPEN_TRANSFER intentionally causes the peer to disconnect shortly after
    // its ACK. Tear down locally now so the runtime cannot treat that expected
    // disconnect as a recoverable link loss or attempt reconnection.
    _token = 0;
    try {
      await link.disconnect();
    } finally {
      _invalidate('Transfer window opened');
    }
  }

  Future<void> cancelTransfer({void Function()? beforeSend}) async {
    _ensureOwnerManagement();
    final generation = _generation;
    await _enqueueCommand(BleOpcode.cancelTransfer, beforeSend: beforeSend);
    _checkGeneration(generation);
  }

  Future<void> setTarget({
    required int ch1,
    required int ch2,
    required int ch3,
    int transitionMs = 200,
    bool latestOnly = true,
  }) async {
    _ensureArmed();
    final payload = BleProtocol.encodeSetTarget(
      ch1: ch1,
      ch2: ch2,
      ch3: ch3,
      transitionMs: transitionMs,
    );
    final targetGeneration = _targetGeneration;
    if (!latestOnly) {
      await _enqueueCommand(
        BleOpcode.setTarget,
        payload: payload,
        targetGeneration: targetGeneration,
      );
      return;
    }
    _latestTarget = payload;
    final old = _latestTargetDone;
    if (old != null && !old.isCompleted) {
      old.completeError(
        const TargetCancelledException('Target superseded by a newer target'),
      );
    }
    final done = _latestTargetDone = Completer<void>();
    if (!_targetPumpScheduled) {
      _targetPumpScheduled = true;
      scheduleMicrotask(_pumpLatestTarget);
    }
    return done.future;
  }

  Future<void> _pumpLatestTarget() async {
    // Keep the pump active while an ACK is outstanding. Touch updates replace
    // the one pending slot instead of building a command/Future queue.
    try {
      while (_latestTarget != null && !_disposed) {
        final generation = _targetGeneration;
        final hz = _snapshot.deviceInfo?.maxTargetHz ?? 20;
        final spacing = Duration(microseconds: 1000000 ~/ hz);
        final last = _lastTargetSentAt;
        if (last != null) {
          final wait = spacing - (_monotonic.elapsed - last);
          if (wait > Duration.zero) await Future<void>.delayed(wait);
        }
        if (generation != _targetGeneration || _latestTarget == null) continue;
        // Keep the pending slot replaceable during the rate-limit wait.
        final payload = _latestTarget!;
        final done = _latestTargetDone!;
        _latestTarget = null;
        _latestTargetDone = null;
        try {
          await _enqueueCommand(
            BleOpcode.setTarget,
            payload: payload,
            targetGeneration: generation,
          );
          if (!done.isCompleted) done.complete();
        } catch (e, st) {
          if (!done.isCompleted) done.completeError(e, st);
        }
      }
    } finally {
      _targetPumpScheduled = false;
      if (_latestTarget != null && !_disposed) {
        _targetPumpScheduled = true;
        scheduleMicrotask(_pumpLatestTarget);
      }
    }
  }

  /// Synchronously invalidates targets that have not reached the transport.
  void cancelPendingTargets() {
    _targetGeneration++;
    _latestTarget = null;
    final done = _latestTargetDone;
    _latestTargetDone = null;
    if (done != null && !done.isCompleted) {
      done.completeError(const TargetCancelledException());
    }
  }

  Future<void> halt() async {
    _ensureReady();
    cancelPendingTargets();
    final generation = _generation;
    await _enqueueCommand(BleOpcode.halt);
    _checkGeneration(generation);
  }

  Future<void> release() async {
    if (_token == 0) return;
    _releaseInProgress = true;
    cancelPendingTargets();
    _keepalive?.cancel();
    _stateRefresh?.cancel();
    try {
      await _enqueueCommand(BleOpcode.release);
    } finally {
      _token = 0;
      await link.disconnect();
      _invalidate('Session released');
    }
  }

  Future<void> disconnect() async {
    _releaseInProgress = true;
    _stateRefresh?.cancel();
    ++_generation;
    cancelPendingTargets();
    _keepalive?.cancel();
    if (_token != 0) {
      try {
        await _enqueueCommand(BleOpcode.release);
      } catch (_) {}
    }
    _token = 0;
    await link.disconnect();
    _invalidate('Disconnected');
  }

  Future<void> _enqueueCommand(
    BleOpcode opcode, {
    List<int>? payload,
    int? targetGeneration,
    void Function()? beforeSend,
  }) {
    final sessionGeneration = _generation;
    final completer = Completer<void>();
    _writeTail = _writeTail.catchError((Object _) {}).then((_) async {
      try {
        _checkGeneration(sessionGeneration);
        if (targetGeneration != null && targetGeneration != _targetGeneration) {
          throw const TargetCancelledException();
        }
        beforeSend?.call();
        await _command(
          opcode,
          token: opcode == BleOpcode.claim ? 0 : _token,
          payload: payload,
          generation: sessionGeneration,
          targetGeneration: targetGeneration,
        );
        _checkGeneration(sessionGeneration);
        if (opcode == BleOpcode.arm || opcode == BleOpcode.halt) {
          final state = await _readSnapshot(sessionGeneration);
          if (state.version != 1 || state.token != _token) {
            unawaited(link.disconnect());
            throw StateError(
              '${opcode.name} StateSnapshot token/version mismatch',
            );
          }
          final phase = opcode == BleOpcode.arm
              ? DeviceSessionPhase.armed
              : DeviceSessionPhase.readyPaused;
          if (opcode == BleOpcode.arm && !state.targetKnown) {
            throw StateError('ARM StateSnapshot has unknown channels');
          }
          _emit(_copy(phase: phase, state: state));
        }
        if (!completer.isCompleted) completer.complete();
      } catch (e, st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<BleEvent> _command(
    BleOpcode opcode, {
    required int token,
    required int generation,
    int? targetGeneration,
    List<int>? payload,
  }) async {
    final ownerManagementCommand =
        opcode == BleOpcode.setPairingCode ||
        opcode == BleOpcode.openTransfer ||
        opcode == BleOpcode.cancelTransfer;
    if (_nextSequence > 0xffffffff) {
      throw StateError('Sequence exhausted; reconnect required');
    }
    final seq = _nextSequence++;
    final bytes = BleProtocol.encodeControlFrame(
      opcode: opcode,
      sequence: seq,
      token: token,
      payload: payload,
    );
    _emit(_copy(sequence: seq));
    Object? lastError;
    var subscriptionRetries = 0;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      _checkGeneration(generation);
      if (targetGeneration != null && targetGeneration != _targetGeneration) {
        throw const TargetCancelledException();
      }
      final waiter = Completer<BleEvent>();
      _pending[seq] = waiter;
      _pendingOpcodes[seq] = opcode.replyValue;
      _pendingTokens[seq] = token;
      var writeCompleted = false;
      try {
        // Future.wait subscribes to the ACK completer before awaiting the
        // write, while bounding the entire write+business-ACK exchange.
        if (opcode == BleOpcode.setTarget) {
          _lastTargetSentAt = _monotonic.elapsed;
        }
        final writeFuture = link.write(BleProtocol.controlRxUuid, bytes);
        unawaited(
          writeFuture.then(
            (_) => writeCompleted = true,
            onError: (Object _) {},
          ),
        );
        final pair = await Future.wait<Object?>([
          writeFuture,
          waiter.future,
        ]).timeout(commandTimeout);
        final event = pair[1] as BleEvent;
        _pending.remove(seq);
        _pendingOpcodes.remove(seq);
        _pendingTokens.remove(seq);
        _checkGeneration(generation);
        if (event.opcode != opcode.replyValue || event.sequence != seq) {
          continue;
        }
        final expectedToken =
            opcode == BleOpcode.claim && event.result == BleResult.ok
            ? event.token
            : token;
        if (event.token != expectedToken ||
            (opcode == BleOpcode.claim &&
                event.result == BleResult.ok &&
                event.token == 0)) {
          continue;
        }
        if (event.result != BleResult.ok) {
          throw BleCommandRejected(opcode, event.result);
        }
        if (opcode == BleOpcode.claim) _token = event.token;
        _emit(
          _copy(token: _token, lastAckSequence: seq, lastAckAt: DateTime.now()),
        );
        return event;
      } catch (e) {
        _pending.remove(seq);
        _pendingOpcodes.remove(seq);
        _pendingTokens.remove(seq);
        _checkGeneration(generation);
        if (e is BleCommandRejected) {
          if (_fatalResult(e.result)) {
            try {
              await link.disconnect();
            } catch (_) {}
          }
          if (opcode == BleOpcode.claim &&
              e.result == BleResult.subscriptionRequired &&
              subscriptionRetries < 20) {
            subscriptionRetries++;
            await Future<void>.delayed(const Duration(milliseconds: 100));
            _checkGeneration(generation);
            attempt--;
            continue;
          }
          rethrow;
        }
        if (e is TargetCancelledException) rethrow;
        if (!writeCompleted) {
          try {
            await link.disconnect();
          } catch (_) {}
          throw StateError(
            ownerManagementCommand
                ? 'Owner-management write did not complete safely'
                : 'BLE write did not complete safely: $e',
          );
        }
        lastError = ownerManagementCommand ? 'transport error' : e;
        if (attempt == maxRetries) break;
      }
    }
    final error = TimeoutException(
      'No business ACK for ${opcode.name} after ${maxRetries + 1} attempts: $lastError',
    );
    // Losing business ACKs means transport state is uncertain. Disconnect so
    // the device lease expires safely and the runtime cannot continue motion.
    try {
      await link.disconnect();
    } catch (_) {}
    throw error;
  }

  Future<void> _refreshState() async {
    if (_releaseInProgress ||
        _stateReadInProgress ||
        _token == 0 ||
        !_snapshot.isConnected ||
        _disposed) {
      return;
    }
    _stateReadInProgress = true;
    final generation = _generation, token = _token;
    try {
      final next = await _readSnapshot(generation);
      if (_releaseInProgress || generation != _generation || token != _token) {
        return;
      }
      if (next.version != 1 || next.token != token) {
        await link.disconnect();
        return;
      }
      _emit(_copy(state: next));
    } catch (_) {
      /* A bounded read failure is retried on the next 2 Hz tick. */
    } finally {
      _stateReadInProgress = false;
    }
  }

  void _onEvent(List<int> bytes) {
    late final BleEvent event;
    try {
      event = BleProtocol.decodeEvent(bytes);
    } catch (_) {
      return;
    }
    if (event.version != 1) return;
    if (event.opcode == 0xe0) {
      // Events carry no channels and are not an atomic state snapshot. The
      // bounded 2 Hz poll updates those fields from StateSnapshot.
      if (_token == 0 || event.token != _token) return;
      return;
    }
    final waiter = _pending[event.sequence];
    if (waiter == null || waiter.isCompleted) return;
    if (event.opcode != _opcodeForPending(event.sequence)) return;
    final reqToken = _pendingTokens[event.sequence];
    if (event.opcode == BleOpcode.claim.replyValue) {
      if (event.result == BleResult.ok ? event.token == 0 : event.token != 0) {
        return;
      }
    } else if (event.token != reqToken) {
      return;
    }
    waiter.complete(event);
  }

  bool _fatalResult(BleResult result) =>
      result == BleResult.badSession ||
      result == BleResult.notAuthorized ||
      result == BleResult.internalError;
  void _notificationFailure(Object error) {
    _fail(error);
    _notificationEnded();
  }

  void _notificationEnded() {
    if (!_disposed &&
        _snapshot.phase != DeviceSessionPhase.disconnected &&
        _snapshot.phase != DeviceSessionPhase.error) {
      unawaited(link.disconnect());
    }
  }

  final Map<int, int> _pendingOpcodes = {};
  int _opcodeForPending(int seq) => _pendingOpcodes[seq] ?? 0;
  void _ensureReady() {
    if (_releaseInProgress || _token == 0 || !_snapshot.isConnected) {
      throw StateError('No claimed BLE session');
    }
  }

  void _ensureArmed() {
    _ensureReady();
    if (!_snapshot.isArmed) {
      throw StateError('ARM is required before SET_TARGET');
    }
  }

  void _ensureOwnerManagement() {
    _ensureReady();
    if (!(_snapshot.deviceInfo?.supportsOwnerManagement ?? false)) {
      throw StateError('Device does not support owner management');
    }
  }

  void _checkGeneration(int g) {
    if (g != _generation) throw StateError('Stale BLE connection operation');
  }

  void _clearPending() {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('Session invalidated'));
    }
    _pending.clear();
    _pendingTokens.clear();
    _pendingOpcodes.clear();
  }

  void _invalidate(String reason) {
    _generation++;
    _releaseInProgress = false;
    _token = 0;
    _keepalive?.cancel();
    _stateRefresh?.cancel();
    _clearPending();
    cancelPendingTargets();
    final notifications = _eventSub;
    _eventSub = null;
    unawaited(notifications?.cancel());
    _emit(
      DeviceSessionSnapshot(
        phase: DeviceSessionPhase.disconnected,
        lastError: reason,
      ),
    );
  }

  void _fail(Object e) {
    _emit(_copy(lastError: e.toString()));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _keepalive?.cancel();
    _stateRefresh?.cancel();
    await _eventSub?.cancel();
    await _linkSub?.cancel();
    await _updates.close();
  }
}
