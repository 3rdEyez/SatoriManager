import 'dart:async';

import 'ble_protocol.dart';
import 'ble_compatibility.dart';
import 'ble_diagnostics.dart';
import 'ota_window.dart';
import 'lan_window.dart';

enum BleLinkState { disconnected, connecting, connected }

/// Small transport contract. Scanning, pairing and platform GATT setup live in
/// the concrete adapter; this class owns the protocol and its single writer.
class BleCharacteristicAbsent implements Exception {
  const BleCharacteristicAbsent();
}

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
  maintenance,
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
    this.diagnostics,
    this.diagnosticsAt,
  });
  final DeviceSessionPhase phase;
  final String? identity;
  final BleDeviceInfo? deviceInfo;
  final BleStateSnapshot? state;
  final int token, sequence;
  final int? lastAckSequence;
  final DateTime? lastAckAt;
  final String? lastError;
  final BleDiagnostics? diagnostics;
  final DateTime? diagnosticsAt;
  bool get isConnected =>
      phase == DeviceSessionPhase.readyPaused ||
      phase == DeviceSessionPhase.armed ||
      phase == DeviceSessionPhase.maintenance;
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
  Timer? _diagnosticRefresh;
  bool _diagnosticReadInProgress = false;
  bool _stateReadInProgress = false;
  bool _releaseInProgress = false;
  bool maintenanceMode = false;
  bool? otaSupported;
  OtaWindowStatus? otaWindow;
  bool? lanSupported;
  LanWindowStatus? lanWindow;
  String? maintenancePath;
  OtaWindowStatus? get activeMaintenanceWindow => maintenancePath == 'unknown'
      ? null
      : maintenancePath == 'lan'
      ? lanWindow
      : otaWindow;
  int? _lanReadGeneration;
  Timer? _lanRefresh;

  Future<void> refreshLanWindow({bool probe = false}) async {
    final generation = _generation;
    if (_lanReadGeneration == generation ||
        (!_snapshot.isConnected && !probe) ||
        _disposed) {
      return;
    }
    _lanReadGeneration = generation;
    try {
      final raw = await link
          .read(LanWindowStatus.lanUuid)
          .timeout(commandTimeout);
      _checkGeneration(generation);
      lanWindow = LanWindowStatus.decode(raw);
      lanSupported = true;
      _emit(_copy());
    } catch (error) {
      if (generation == _generation) {
        if (probe) {
          lanSupported = error is BleCharacteristicAbsent ? false : null;
        }
        lanWindow = null;
        _emit(_copy());
      }
    } finally {
      if (_lanReadGeneration == generation) _lanReadGeneration = null;
    }
  }

  Future<void> changeLanWindow(
    bool open, {
    String ssid = '',
    String password = '',
  }) {
    if (_otaOperation != null) return Future.error(StateError('升级操作正在进行'));
    // Validate locally without mutating the session or sending credentials.
    LanWindowStatus.lanRequest(
      open: open,
      requestId: 1,
      windowId: open ? 0 : (lanWindow?.windowId ?? 0),
      ssid: ssid,
      password: password,
    );
    return _otaOperation = _changeOtaWindow(
      open,
      lan: true,
      ssid: ssid,
      password: password,
    ).whenComplete(() => _otaOperation = null);
  }

  Timer? _otaRefresh;
  int? _otaReadGeneration;
  int _otaRequestId = DateTime.now().microsecondsSinceEpoch & 0xffffffff;
  Future<void>? _otaOperation;

  Future<void> refreshOtaWindow({bool probe = false}) async {
    final generation = _generation;
    if (_otaReadGeneration == generation ||
        (!_snapshot.isConnected && !probe) ||
        _disposed) {
      return;
    }
    _otaReadGeneration = generation;
    try {
      final raw = await link.read(OtaWindowStatus.uuid).timeout(commandTimeout);
      _checkGeneration(generation);
      otaWindow = OtaWindowStatus.decode(raw);
      otaSupported = true;
      _emit(_copy());
    } catch (error) {
      if (generation == _generation) {
        if (probe) {
          otaSupported = error is BleCharacteristicAbsent ? false : null;
        }
        otaWindow =
            null; // A failed read never leaves credentials/status fresh.
        _emit(_copy());
      }
    } finally {
      if (_otaReadGeneration == generation) _otaReadGeneration = null;
    }
  }

  Future<void> changeOtaWindow(bool open) {
    if (_otaOperation != null) return Future.error(StateError('升级操作正在进行'));
    return _otaOperation = _changeOtaWindow(
      open,
    ).whenComplete(() => _otaOperation = null);
  }

  Future<void> _changeOtaWindow(
    bool open, {
    bool lan = false,
    String ssid = '',
    String password = '',
  }) async {
    if (maintenancePath == 'unknown') {
      throw StateError('维护状态未确认，请重新连接确认');
    }
    final current = lan ? lanWindow : otaWindow;
    final other = lan ? otaWindow : lanWindow;
    if (open &&
        (other != null && !other.isClosed ||
            maintenanceMode &&
                maintenancePath != null &&
                maintenancePath != (lan ? 'lan' : 'ap'))) {
      throw StateError('请先确认并关闭当前维护窗口');
    }
    if ((lan ? lanSupported : otaSupported) != true || !_snapshot.isConnected) {
      throw StateError('当前固件或连接不支持无线升级');
    }
    if (open && current?.signingReady != true) {
      throw StateError('固件签名升级尚未就绪');
    }
    if (!open && current?.isCommitted == true) {
      throw StateError('镜像已提交，不能声称取消升级');
    }
    if (open && maintenanceMode && current?.isOpen == true) return;
    final window = open ? 0 : current?.windowId;
    if (window == null || (!open && window == 0 && current?.isClosed != true)) {
      throw StateError('窗口状态未知，无法确认关闭');
    }
    final generation = _generation;
    maintenanceMode = true;
    maintenancePath = lan ? 'lan' : 'ap';
    cancelPendingTargets();
    _keepalive?.cancel();
    _stateRefresh?.cancel();
    _diagnosticRefresh?.cancel();
    _token = 0;
    _emit(_copy(phase: DeviceSessionPhase.maintenance, token: 0));
    _otaRequestId = (_otaRequestId + 1) & 0xffffffff;
    if (_otaRequestId == 0) _otaRequestId = 1;
    final id = _otaRequestId;
    final bytes = lan
        ? LanWindowStatus.lanRequest(
            open: open,
            requestId: id,
            windowId: window,
            ssid: ssid,
            password: password,
          )
        : OtaWindowStatus.request(open: open, requestId: id, windowId: window);
    final uuid = lan ? LanWindowStatus.lanUuid : OtaWindowStatus.uuid;
    final done = Completer<void>();
    _writeTail = _writeTail.catchError((Object _) {}).then((_) async {
      try {
        if (bytes.length > 20 && link is BleLargeWriteLink) {
          await (link as BleLargeWriteLink)
              .prepareLargeWrite(bytes.length)
              .timeout(const Duration(seconds: 3));
          _checkGeneration(generation);
        }
        final deadline = DateTime.now().add(Duration(seconds: lan ? 26 : 12));
        var acknowledged = false;
        for (var attempt = 0; attempt < 4; attempt++) {
          _checkGeneration(generation);
          if (!_snapshot.isConnected) throw StateError('升级蓝牙连接已断开');
          // A timeout can mean accepted: reconcile via status before retrying.
          try {
            if (!acknowledged) {
              await link.write(uuid, bytes).timeout(commandTimeout);
            }
          } catch (_) {
            _checkGeneration(generation);
          }
          for (var poll = 0; poll < (lan ? 140 : 4); poll++) {
            if (DateTime.now().isAfter(deadline)) break;
            if (lan) {
              await refreshLanWindow();
            } else {
              await refreshOtaWindow();
            }
            _checkGeneration(generation);
            final status = lan ? lanWindow : otaWindow;
            if (status != null && status.ackRequestId == id) {
              acknowledged = true;
              if (status.result != 0) {
                throw StateError('升级请求被设备拒绝（代码 ${status.result}）');
              }
              if (open ? status.isOpen : status.isClosed) {
                if (!done.isCompleted) done.complete();
                return;
              }
              if (status.isCommitted || status.state == 6) {
                throw StateError('设备未完成请求的窗口操作');
              }
            }
            await Future<void>.delayed(const Duration(milliseconds: 150));
            if (lan && !acknowledged && poll >= 3) break;
          }
        }
        throw StateError(open ? '开启未确认；设备可能已开窗，请查看窗口状态' : '关闭未确认；设备窗口可能仍有效');
      } catch (error, stack) {
        if (!done.isCompleted) done.completeError(error, stack);
      }
    });
    return done.future;
  }

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
    BleDiagnostics? diagnostics,
    DateTime? diagnosticsAt,
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
    diagnostics: diagnostics ?? _snapshot.diagnostics,
    diagnosticsAt: diagnosticsAt ?? _snapshot.diagnosticsAt,
  );

  Future<void> connect(String id, {String? expectedIdentity}) async {
    final generation = ++_generation;
    maintenanceMode = false;
    otaSupported = null;
    otaWindow = null;
    lanWindow = null;
    lanSupported = null;
    maintenancePath = null;
    _lanRefresh?.cancel();
    _otaRefresh?.cancel();
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
      final mismatch = BleCompatibility.incompatibility(info);
      if (mismatch != null) {
        throw BleVersionMismatch(info, mismatch);
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
      await refreshLanWindow(probe: true);
      _checkGeneration(generation);
      if (lanSupported == true) {
        _lanRefresh = Timer.periodic(
          const Duration(seconds: 1),
          (_) => refreshLanWindow(),
        );
      }
      await refreshOtaWindow(probe: true);
      _checkGeneration(generation);
      if (otaSupported == true) {
        _otaRefresh = Timer.periodic(
          const Duration(seconds: 1),
          (_) => refreshOtaWindow(),
        );
      }
      if (lanSupported == null || otaSupported == null) {
        maintenancePath = 'unknown';
        maintenanceMode = true;
        _emit(_copy(phase: DeviceSessionPhase.maintenance, token: 0));
        return; // Unknown optional reads must never grant control.
      }
      if ((lanWindow != null && !lanWindow!.isClosed) ||
          (otaWindow != null && !otaWindow!.isClosed)) {
        maintenancePath = lanWindow != null && !lanWindow!.isClosed
            ? 'lan'
            : 'ap';
        maintenanceMode = true;
        _emit(_copy(phase: DeviceSessionPhase.maintenance, token: 0));
        return; // Authenticated maintenance needs no CLAIM or ARM.
      }
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
      // Optional patch-level extension. Reads cannot renew the safety lease;
      // a missing/failed characteristic never blocks ARM or the heartbeat.
      _diagnosticRefresh?.cancel();
      if (info.firmwarePatch >= 3) {
        unawaited(_refreshDiagnostics());
        _diagnosticRefresh = Timer.periodic(
          const Duration(seconds: 5),
          (_) => _refreshDiagnostics(),
        );
      }
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
    _diagnosticRefresh?.cancel();
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
    _diagnosticRefresh?.cancel();
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
        if (maintenanceMode) throw StateError('升级维护中，控制会话已暂停');
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

  Future<void> _refreshDiagnostics() async {
    if (_releaseInProgress ||
        _diagnosticReadInProgress ||
        !_snapshot.isConnected ||
        _disposed) {
      return;
    }
    _diagnosticReadInProgress = true;
    final generation = _generation;
    try {
      final bytes = await link
          .read(BleDiagnostics.uuid)
          .timeout(const Duration(milliseconds: 500));
      if (generation != _generation || _releaseInProgress || _disposed) return;
      _emit(
        _copy(
          diagnostics: BleDiagnostics.decode(bytes),
          diagnosticsAt: DateTime.now(),
        ),
      );
    } catch (_) {
      // Keep the last timestamp, so old samples can never appear fresh.
    } finally {
      _diagnosticReadInProgress = false;
    }
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
    _diagnosticRefresh?.cancel();
    _otaRefresh?.cancel();
    _lanRefresh?.cancel();
    lanWindow = null;
    otaWindow = null;
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
    _otaRefresh?.cancel();
    _lanRefresh?.cancel();
    lanWindow = null;
    otaWindow = null;
    _generation++;
    _keepalive?.cancel();
    _stateRefresh?.cancel();
    _diagnosticRefresh?.cancel();
    await _eventSub?.cancel();
    await _linkSub?.cancel();
    await _updates.close();
  }
}
