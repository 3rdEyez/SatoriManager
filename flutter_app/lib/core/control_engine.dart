import 'dart:async';
import 'dart:math';
import 'ble_protocol.dart' show BleResult;
import 'ble_compatibility.dart';
import 'device_session.dart';
import 'protocol.dart' show ActionFrame, Protocol;
import 'safety_limits.dart';

typedef MonotonicClock = Duration Function();
typedef Schedule = Timer Function(Duration delay, void Function() callback);

/// One service-owned action engine. UI lifecycle never owns its timers.
class ControlEngine {
  ControlEngine(
    this.session,
    this.actions, {
    MonotonicClock? clock,
    Schedule? schedule,
    Random? random,
  }) : now = clock ?? (Stopwatch()..start()).elapsedGetter,
       later = schedule ?? Timer.new,
       random = random ?? Random() {
    _subscription = session.snapshots.listen(_sessionChanged);
  }
  final DeviceSession session;
  final Map<String, List<ActionFrame>> actions;
  final MonotonicClock now;
  final Schedule later;
  final Random random;
  final _updates = StreamController<Map<String, Object?>>.broadcast();
  Stream<Map<String, Object?>> get updates => _updates.stream;
  late final StreamSubscription<DeviceSessionSnapshot> _subscription;
  final runtimeId =
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
  int revision = 0;
  String connection = 'disconnected';
  String mode = 'manual';
  String playback = 'idle';
  bool autoRotate = false;
  bool autoWink = false;
  bool outputAuthorized = false;
  String? error;
  String? issueCode;
  String? incompatibleFirmware;
  String? incompatibleProtocol;
  bool pauseInProgress = false;
  bool otaMaintenance = false;
  bool otaBusy = false;
  bool _otaResumeBlocked = false;
  String? otaNotice;
  bool explicitlyPaused = false;
  String? endState;
  String? deviceId;
  String? _identity;
  SafetyLimits? safety;
  List<int>? target;
  int _motionGeneration = 0;
  int _connectionGeneration = 0;
  int _autoStartGeneration = 0;
  bool _autoStartPending = false;
  bool _connecting = false;
  bool _ending = false;
  bool _disposed = false;
  bool _pairingOperation = false;
  String? pairingNotice;
  Timer? _rotate;
  Timer? _wink;
  Timer? _frame;
  Timer? _reconnect;
  int _reconnectAttempt = 0;
  Future<void>? _disconnecting;

  Map<String, Object?> snapshot() {
    final s = session.snapshot;
    return {
      'runtimeId': runtimeId,
      'revision': revision,
      'connection': connection,
      'sessionPhase': s.phase.name,
      'deviceId': deviceId,
      'identity': s.identity,
      'firmware': s.deviceInfo?.firmwareVersion ?? incompatibleFirmware,
      'deviceProtocol': s.deviceInfo?.protocolVersion ?? incompatibleProtocol,
      'appVersion': BleCompatibility.appVersion,
      'appProtocol': BleCompatibility.protocolVersion,
      'supportsOwnerManagement':
          ((s.deviceInfo?.capabilities ?? 0) & 0x80) != 0,
      'supportsSharedPairing': s.deviceInfo?.supportsSharedPairing ?? false,
      'pairingNotice': pairingNotice,
      'supportsSavedNetwork': s.isConnected && session.supportsSavedNetwork,
      'hasSavedNetwork': s.isConnected && session.hasSavedNetwork,
      'lanSupported': s.isConnected ? session.lanSupported : null,
      'lanWindow': s.isConnected ? session.lanWindow?.toUiJson() : null,
      'maintenancePath': session.maintenancePath,
      'otaSupported': s.isConnected ? session.otaSupported : null,
      'otaWindow': s.isConnected ? session.otaWindow?.toUiJson() : null,
      'otaMaintenance': otaMaintenance,
      'otaBusy': otaBusy,
      'otaNotice': otaNotice,
      'maxTargetHz': s.deviceInfo?.maxTargetHz,
      'mode': mode,
      'playback': playback,
      'autoRotate': autoRotate,
      'autoWink': autoWink,
      'outputAuthorized': outputAuthorized,
      'target': target,
      'lastCommanded': s.state?.channels,
      'validChannelMask': s.state?.validChannelMask ?? 0,
      'lastAppliedSequence': s.state?.lastAppliedSequence,
      'lastAckSequence': s.lastAckSequence,
      'lastAckAt': s.lastAckAt?.toIso8601String(),
      'battery': s.state?.batteryPercent,
      'diagnostics': s.diagnostics?.toJson(),
      'diagnosticsAt': s.diagnosticsAt?.toIso8601String(),
      'endState': endState,
      'safety': safety?.toJson(),
      'error': error ?? s.lastError,
      'issueCode': issueCode,
      'controlPhase': pauseInProgress
          ? 'pausing'
          : issueCode == 'pauseUnconfirmed'
          ? 'pauseUnconfirmed'
          : issueCode == 'configuration'
          ? 'configurationError'
          : issueCode == 'outputUnconfirmed'
          ? 'outputUnconfirmed'
          : issueCode == 'outputFailed'
          ? 'ready'
          : issueCode == 'actionFailed'
          ? 'actionFailed'
          : outputAuthorized
          ? 'active'
          : explicitlyPaused
          ? 'paused'
          : 'preparing',
    };
  }

  void _notify() {
    if (_disposed) return;
    revision++;
    _updates.add(snapshot());
  }

  void _sessionChanged(DeviceSessionSnapshot s) {
    if (_disposed || !identical(s, session.snapshot)) return;
    if (!_connecting &&
        !_ending &&
        connection == 'connected' &&
        !s.isConnected) {
      _cancelMotion();
      outputAuthorized = false;
      target = null;
      if (otaMaintenance) {
        connection = 'disconnected';
        otaNotice = '蓝牙已断开，窗口状态未知；浏览器上传不依赖蓝牙。请等窗口自动超时。';
        _autoStartPending = false;
        _notify();
        return;
      }
      connection = 'reconnecting';
      error = '连接中断，动作已取消';
      _reconnectAttempt = 0;
      // A disconnect creates one recovery auto-start intent. Every retry in
      // this backoff round shares it, so a pause can revoke it permanently.
      final autoStartGeneration = ++_autoStartGeneration;
      _autoStartPending = !_otaResumeBlocked;
      _scheduleReconnect(_connectionGeneration, autoStartGeneration);
    }
    _notify();
  }

  Future<void> connect(
    String id, {
    SafetyLimits? limits,
    bool autoStart = true,
    String? expectedIdentity,
    Future<SafetyLimits?> Function(String identity)? safetyForIdentity,
  }) async {
    if (_connecting ||
        connection == 'connected' ||
        connection == 'reconnecting') {
      throw StateError('请先结束当前连接');
    }
    autoStart = autoStart && !_otaResumeBlocked;
    endState = null;
    otaNotice = null;
    otaMaintenance = false;
    _ending = false;
    _reconnect?.cancel();
    final generation = ++_connectionGeneration;
    final autoStartGeneration = ++_autoStartGeneration;
    _autoStartPending = autoStart;
    _cancelMotion();
    outputAuthorized = false;
    explicitlyPaused = !autoStart;
    target = null;
    safety = limits ?? SafetyLimits.builtInSatoriC3;
    deviceId = id;
    _identity = expectedIdentity;
    connection = 'connecting';
    error = null;
    issueCode = null;
    incompatibleFirmware = null;
    incompatibleProtocol = null;
    _connecting = true;
    _notify();
    try {
      await session.connect(id, expectedIdentity: _identity);
      if (generation != _connectionGeneration) throw StateError('连接操作已取消');
      _checkIdentity();
      final authenticatedIdentity = session.snapshot.identity;
      if (safetyForIdentity != null && authenticatedIdentity != null) {
        safety =
            await safetyForIdentity(authenticatedIdentity) ??
            SafetyLimits.builtInSatoriC3;
        if (generation != _connectionGeneration) {
          throw StateError('连接操作已取消');
        }
      }
      connection = 'connected';
      _identity = authenticatedIdentity;
      if (session.maintenanceMode) {
        otaMaintenance = true;
        _otaResumeBlocked = true;
        _autoStartPending = false;
        explicitlyPaused = true;
      }
      await _tryAutoStart(autoStartGeneration);
    } catch (e) {
      if (generation == _connectionGeneration) {
        connection = 'failed';
        error = '$e';
        if (e is BleVersionMismatch) {
          issueCode = 'versionMismatch';
          incompatibleFirmware = e.deviceInfo.firmwareVersion;
          incompatibleProtocol = e.deviceInfo.protocolVersion;
        }
        await session.disconnect();
      }
      rethrow;
    } finally {
      if (generation == _connectionGeneration) _connecting = false;
      _notify();
    }
  }

  void _checkIdentity() {
    if (_identity != null && session.snapshot.identity != _identity) {
      throw StateError('认证后的设备身份与收藏不符');
    }
  }

  Future<void> configureSafety(SafetyLimits limits) async {
    if (outputAuthorized) throw StateError('暂停后再修改安全范围');
    safety = limits;
    _notify();
    if (_autoStartPending && connection == 'connected') {
      await _tryAutoStart(_autoStartGeneration);
    }
  }

  Future<void> _tryAutoStart(int generation) async {
    if (generation != _autoStartGeneration ||
        !_autoStartPending ||
        _otaResumeBlocked) {
      return;
    }
    if (connection != 'connected') return;
    safety ??= SafetyLimits.builtInSatoriC3;
    _autoStartPending = false;
    _notify();
    try {
      await _arm(generation, autoStart: true);
      if (!session.snapshot.isConnected) {
        outputAuthorized = false;
        target = null;
        throw StateError('BLE disconnected during automatic ARM');
      }
    } catch (e) {
      if (generation == _autoStartGeneration) {
        if (!session.snapshot.isConnected) {
          outputAuthorized = false;
          target = null;
          rethrow;
        }
        final notConfigured =
            e is BleCommandRejected && e.result == BleResult.notConfigured;
        var haltConfirmed = false;
        if (!notConfigured && session.snapshot.isConnected) {
          try {
            await session.halt();
            haltConfirmed = true;
          } catch (_) {
            // Preserve an explicit uncertainty message below.
          }
        }
        error = notConfigured
            ? '设备尚未配置已验证的启动姿态，已保持暂停。请先完成 USB 维护配置。'
            : haltConfirmed
            ? '自动启用输出失败，已确认设备暂停：$e'
            : '自动启用输出状态未确认，请检查设备连接并手动暂停：$e';
        issueCode = notConfigured
            ? 'configuration'
            : haltConfirmed
            ? 'outputFailed'
            : 'outputUnconfirmed';
        outputAuthorized = false;
        target = null;
        _notify();
      }
    }
  }

  Future<void> arm() async {
    if (outputAuthorized) return;
    await _arm(_autoStartGeneration, autoStart: false);
    _otaResumeBlocked = false;
  }

  Future<void> _arm(int autoStartGeneration, {required bool autoStart}) async {
    if (otaMaintenance || otaBusy) throw StateError('请先确认关闭并退出升级模式');
    if (_pairingOperation) throw StateError('配对设置处理中，请稍候');
    if (connection != 'connected') throw StateError('设备尚未就绪');
    safety ??= SafetyLimits.builtInSatoriC3;
    final generation = _motionGeneration;
    final connectionGeneration = _connectionGeneration;
    error = null;
    issueCode = null;
    await session.arm(
      beforeSend: () {
        if (generation != _motionGeneration ||
            connectionGeneration != _connectionGeneration ||
            (autoStart && autoStartGeneration != _autoStartGeneration)) {
          throw const TargetCancelledException(
            'ARM was cancelled before transmission',
          );
        }
      },
    );
    if (generation != _motionGeneration ||
        connectionGeneration != _connectionGeneration ||
        (autoStart && autoStartGeneration != _autoStartGeneration)) {
      return;
    }
    final state = session.snapshot.state;
    if (state == null || state.validChannelMask != 7) {
      throw StateError('设备未返回有效启动输出');
    }
    if (!safety!.contains(state.channels)) {
      await session.halt();
      throw StateError('设备启动输出不在已确认范围内，请核对机械配置');
    }
    target = List.of(state.channels);
    outputAuthorized = true;
    explicitlyPaused = false;
    _notify();
  }

  void _requireControl() {
    if (otaMaintenance ||
        otaBusy ||
        _pairingOperation ||
        connection != 'connected' ||
        !outputAuthorized ||
        target == null ||
        safety == null) {
      throw StateError('设备未就绪或尚未确认安全范围');
    }
  }

  Future<void> setManual(List<num> proportions) async {
    _requireControl();
    final next = _merge(proportions);
    _cancelMotion();
    mode = 'manual';
    try {
      await _send(
        next,
        generation: _motionGeneration,
        latestOnly: true,
        transitionMs: 50,
      );
    } on TargetCancelledException {
      // A newer manual point or stop superseded this unsent point.
    }
  }

  List<int> _merge(List<num> proportions) {
    if (proportions.length != 3) throw const FormatException('需要三个通道');
    return [
      for (var i = 0; i < 3; i++)
        proportions[i] == -1 ? target![i] : Protocol.proportion(proportions[i]),
    ];
  }

  Future<void> _send(
    List<int> next, {
    required int generation,
    bool latestOnly = false,
    int transitionMs = 200,
  }) async {
    _requireControl();
    if (generation != _motionGeneration) return;
    final constrained = safety!.constrain(next);
    target = constrained;
    _notify();
    await session.setTarget(
      ch1: constrained[0],
      ch2: constrained[1],
      ch3: constrained[2],
      transitionMs: min(
        transitionMs,
        session.snapshot.deviceInfo?.maxTransitionMs ?? 200,
      ),
      latestOnly: latestOnly,
    );
  }

  void setAutoRotate(bool enabled) {
    _requireControl();
    _rotate?.cancel();
    autoRotate = enabled;
    mode = autoRotate || autoWink ? 'auto' : 'manual';
    if (enabled) _rotateTick(_motionGeneration);
    _notify();
  }

  void _rotateTick(int generation) {
    if (generation != _motionGeneration || !autoRotate || !outputAuthorized) {
      return;
    }
    if (playback != 'playing') {
      final next = List<int>.of(target!);
      for (var i = 0; i < 2; i++) {
        final low = safety!.minimum[i];
        final high = safety!.maximum[i];
        next[i] = (low + (high - low) * (.375 + random.nextDouble() * .25))
            .round();
      }
      unawaited(
        _guardAction(
          _send(next, generation: generation, latestOnly: true),
          generation,
        ),
      );
    }
    _rotate = later(const Duration(seconds: 5), () => _rotateTick(generation));
  }

  void setAutoWink(bool enabled) {
    _requireControl();
    _wink?.cancel();
    autoWink = enabled;
    mode = autoRotate || autoWink ? 'auto' : 'manual';
    if (enabled) {
      _wink = later(
        const Duration(seconds: 5),
        () => _winkTick(_motionGeneration),
      );
    }
    _notify();
  }

  void _winkTick(int generation) {
    if (generation != _motionGeneration || !autoWink || !outputAuthorized) {
      return;
    }
    if (playback == 'idle') play(random.nextBool() ? 'wink' : 'wink2');
    _wink = later(const Duration(seconds: 5), () => _winkTick(generation));
  }

  void play(String name) {
    _requireControl();
    final frames = actions[name];
    if (frames == null) throw StateError('未知动作 $name');
    if (playback == 'playing') return;
    session.cancelPendingTargets();
    playback = 'playing';
    final generation = _motionGeneration;
    _notify();
    unawaited(_guardAction(_step(frames, 0, now(), generation), generation));
  }

  Future<void> _step(
    List<ActionFrame> frames,
    int index,
    Duration due,
    int generation,
  ) async {
    if (generation != _motionGeneration || !outputAuthorized) return;
    if (index >= frames.length) {
      playback = 'idle';
      _notify();
      return;
    }
    if (now() - due > const Duration(milliseconds: 100)) {
      throw TimeoutException('动作关键帧已过期，剩余动作已取消');
    }
    final frame = frames[index];
    await _send(_merge(frame.channels), generation: generation);
    if (generation != _motionGeneration || !outputAuthorized) return;
    final nextDue = due + frame.duration;
    final delay = nextDue - now();
    _frame = later(delay.isNegative ? Duration.zero : delay, () {
      unawaited(
        _guardAction(_step(frames, index + 1, nextDue, generation), generation),
      );
    });
  }

  Future<void> _guardAction(Future<void> work, int generation) async {
    try {
      await work;
    } on TargetCancelledException {
      // Preset/manual priority may replace an unsent automatic target.
    } catch (e) {
      if (generation != _motionGeneration || _disposed) return;
      final actionError = '$e';
      try {
        await stopMotion();
      } catch (_) {
        /* stopMotion retains unconfirmed state */
      }
      if (issueCode == null && !outputAuthorized) {
        error = actionError;
        issueCode = 'actionFailed';
        _notify();
      }
    }
  }

  void _cancelMotion() {
    _motionGeneration++;
    _frame?.cancel();
    _rotate?.cancel();
    _wink?.cancel();
    session.cancelPendingTargets();
    autoRotate = false;
    autoWink = false;
    playback = 'idle';
    mode = 'manual';
  }

  Future<void> stopMotion() async {
    _autoStartPending = false;
    ++_autoStartGeneration;
    _cancelMotion();
    outputAuthorized = false;
    explicitlyPaused = true;
    pauseInProgress = true;
    issueCode = null;
    error = null;
    _notify();
    // A stop issued while a connection is still being established cancels
    // that generation's automatic ARM. There is no claimed session to HALT.
    if (!session.snapshot.isConnected) {
      pauseInProgress = false;
      _notify();
      return;
    }
    try {
      await session.halt();
    } catch (e) {
      error = '暂停未确认：$e';
      issueCode = 'pauseUnconfirmed';
      _notify();
      rethrow;
    } finally {
      pauseInProgress = false;
      _notify();
    }
    _notify();
  }

  void _scheduleReconnect(int generation, int autoStartGeneration) {
    const delays = [1, 2, 4, 8];
    if (_reconnectAttempt == delays.length) {
      connection = 'failed';
      error = '恢复失败，请手动重新连接';
      _notify();
      return;
    }
    final delay = delays[_reconnectAttempt++];
    _reconnect = later(Duration(seconds: delay), () async {
      if (generation != _connectionGeneration || _ending || _disposed) return;
      _connecting = true;
      try {
        await session.disconnect();
        if (generation != _connectionGeneration || _ending) return;
        await session.connect(deviceId!, expectedIdentity: _identity);
        if (generation != _connectionGeneration || _ending) return;
        _checkIdentity();
        connection = 'connected';
        await _tryAutoStart(autoStartGeneration);
        if (outputAuthorized) {
          error = null;
        } else if (safety != null && error == null) {
          error = '连接已恢复，输出保持暂停';
        }
      } catch (e) {
        if (generation != _connectionGeneration || _ending) return;
        error = '$e';
        await session.disconnect();
        if (generation == _connectionGeneration && !_ending) {
          if (autoStartGeneration == _autoStartGeneration) {
            // A failed attempt may not have reached ARM. Keep the intent for
            // the next retry unless pause has advanced the generation.
            _autoStartPending = !_otaResumeBlocked;
          }
          _scheduleReconnect(generation, autoStartGeneration);
        }
      } finally {
        if (generation == _connectionGeneration) _connecting = false;
        _notify();
      }
    });
  }

  void _requireOwnerManagement() {
    if (_pairingOperation) throw StateError('配对设置处理中，请稍候');
    if (connection != 'connected') throw StateError('请先连接已绑定的设备');
    if (((session.snapshot.deviceInfo?.capabilities ?? 0) & 0x80) == 0) {
      throw StateError('设备固件不支持手机管理配对，请先升级固件');
    }
  }

  Future<void> setPairingCode(
    String code, {
    void Function()? ensureCurrentClient,
  }) async {
    _requireOwnerManagement();
    if (!RegExp(r'^[0-9]{6}$').hasMatch(code) || code == '123456') {
      throw const FormatException('请输入六位数字的新码，不能使用默认码');
    }
    _pairingOperation = true;
    final generation = _connectionGeneration;
    try {
      await stopMotion();
      if (generation != _connectionGeneration || _ending) {
        throw StateError('配对设置操作已取消');
      }
      ensureCurrentClient?.call();
      await session.setPairingCode(code, beforeSend: ensureCurrentClient);
      pairingNotice = '配对码已保存。当前手机仍保持绑定，动作保持暂停。';
      error = null;
    } catch (_) {
      error = '配对码修改未确认，请重新连接后重试';
      rethrow;
    } finally {
      _pairingOperation = false;
      _notify();
    }
  }

  Future<void> cancelTransfer({void Function()? ensureCurrentClient}) async {
    _requireOwnerManagement();
    _pairingOperation = true;
    final generation = _connectionGeneration;
    try {
      await stopMotion();
      if (generation != _connectionGeneration || _ending) {
        throw StateError('取消换绑操作已取消');
      }
      ensureCurrentClient?.call();
      await session.cancelTransfer(beforeSend: ensureCurrentClient);
      pairingNotice = '换绑窗口已关闭，当前手机继续作为主控。';
      error = null;
    } finally {
      _pairingOperation = false;
      _notify();
    }
  }

  Future<void> openTransfer({void Function()? ensureCurrentClient}) async {
    _requireOwnerManagement();
    _pairingOperation = true;
    var attemptedTransfer = false;
    _ending =
        true; // Expected transfer disconnect must never reconnect the old phone.
    final generation = ++_connectionGeneration;
    _reconnect?.cancel();
    _cancelMotion();
    outputAuthorized = false;
    try {
      await session.halt();
      if (generation != _connectionGeneration) {
        throw StateError('换绑操作已取消');
      }
      ensureCurrentClient?.call();
      await session.openTransfer(
        beforeSend: () {
          ensureCurrentClient?.call();
          attemptedTransfer = true;
        },
      );
      pairingNotice = '已开启60秒换绑窗口。请立即用新手机和修改后的配对码连接；超时仍保留旧手机绑定。';
      error = null;
    } catch (_) {
      error = '开启换绑未确认；请用原手机重新连接。若尚未修改默认码，请先修改。';
      pairingNotice = null;
      rethrow;
    } finally {
      if (attemptedTransfer) {
        await session.disconnect();
        connection = 'disconnected';
        target = null;
      } else {
        _ending = false;
        connection = session.snapshot.isConnected
            ? 'connected'
            : 'disconnected';
      }
      _pairingOperation = false;
      _notify();
    }
  }

  Future<void> openOtaWindow({
    bool lan = false,
    String ssid = '',
    String password = '',
    bool useSavedNetwork = false,
    bool rememberNetwork = false,
    void Function()? ensureCurrentClient,
  }) async {
    if (otaBusy) throw StateError('升级操作正在进行');
    if ((lan ? session.lanSupported : session.otaSupported) != true ||
        connection != 'connected') {
      throw StateError('当前固件不支持无线升级窗口');
    }
    if ((useSavedNetwork || rememberNetwork) &&
        (!lan || !session.supportsSavedNetwork)) {
      throw StateError('固件不支持已保存网络');
    }
    otaBusy = true;
    _otaResumeBlocked = true;
    otaNotice = null;
    final wasMaintenance = otaMaintenance;
    otaMaintenance = true; // Also protect a disconnect while HALT is pending.
    _autoStartPending = false;
    ++_autoStartGeneration;
    _reconnect?.cancel();
    try {
      if (!wasMaintenance) await stopMotion();
      _autoStartPending = false;
      ++_autoStartGeneration;
      _reconnect?.cancel();
      ensureCurrentClient?.call();
      if (lan) {
        await session.changeLanWindow(
          true,
          ssid: ssid,
          password: password,
          useSavedNetwork: useSavedNetwork,
          rememberNetwork: rememberNetwork,
        );
      } else {
        await session.changeOtaWindow(true);
      }
      otaNotice = lan
          ? '设备已确认连接局域网并开启限时维护；电脑可直接打开设备地址。'
          : '备用热点窗口已由设备确认开启；按下面指引在浏览器上传签名升级包。';
    } catch (_) {
      otaNotice = '开启未确认；请查看设备状态。不要把写入成功当作已开窗。';
      rethrow;
    } finally {
      otaBusy = false;
      _notify();
    }
  }

  Future<void> closeOtaWindow({void Function()? ensureCurrentClient}) async {
    if (otaBusy) throw StateError('升级操作正在进行');
    otaBusy = true;
    final wasMaintenance = otaMaintenance;
    otaMaintenance = true;
    _otaResumeBlocked = true;
    try {
      if (!wasMaintenance) await stopMotion();
      ensureCurrentClient?.call();
      if (session.maintenancePath == 'lan') {
        await session.changeLanWindow(false);
      } else {
        await session.changeOtaWindow(false);
      }
      otaNotice = '设备已确认窗口关闭；控制仍暂停。退出升级后可重新连接。';
    } catch (_) {
      otaNotice = session.activeMaintenanceWindow?.isCommitted == true
          ? '镜像已提交，不能取消或声称撤销；等待设备重启。'
          : '关闭未确认；窗口可能仍有效，请等待自动超时。';
      rethrow;
    } finally {
      otaBusy = false;
      _notify();
    }
  }

  Future<void> reconnectOtaMaintenance() async {
    final unknown = session.maintenancePath == 'unknown';
    if (otaBusy ||
        (!unknown && connection != 'disconnected' && connection != 'failed')) {
      throw StateError('当前不能重新连接');
    }
    final id = deviceId;
    if (id == null || !_otaResumeBlocked) throw StateError('没有可恢复的升级会话');
    if (unknown) {
      await session.disconnect();
      connection = 'disconnected';
    }
    await connect(
      id,
      expectedIdentity: _identity,
      limits: safety,
      autoStart: false,
    );
    otaNotice = session.activeMaintenanceWindow == null
        ? '已连接，但升级窗口状态未确认；控制保持暂停。'
        : '已从设备重新读取窗口状态；控制保持暂停。';
    _notify();
  }

  Future<void> exitOtaMaintenance() async {
    if (otaBusy) throw StateError('升级操作正在进行');
    if (connection != 'connected' ||
        session.activeMaintenanceWindow?.isClosed != true) {
      throw StateError('必须先由设备确认窗口关闭；蓝牙断开时请等待超时后重新连接');
    }
    final id = deviceId, identity = _identity, limits = safety;
    if (id == null) throw StateError('设备身份未知');
    _ending = true;
    await session.disconnect();
    connection = 'disconnected';
    await connect(
      id,
      expectedIdentity: identity,
      limits: limits,
      autoStart: false,
    );
    otaNotice = '已退出升级并建立新会话；保持暂停，需手动启用控制。';
    _notify();
  }

  Future<void> disconnect() => _disconnecting ??= _disconnect().whenComplete(
    () => _disconnecting = null,
  );

  Future<void> _disconnect() async {
    if (_ending && connection == 'disconnected' && endState != null) return;
    _ending = true;
    ++_connectionGeneration;
    ++_autoStartGeneration;
    _autoStartPending = false;
    _connecting = false;
    _reconnect?.cancel();
    _cancelMotion();
    outputAuthorized = false;
    explicitlyPaused = true;
    final hadSession =
        session.snapshot.isConnected && session.snapshot.token != 0;
    endState = 'ending';
    error = null;
    issueCode = null;
    _notify();
    try {
      await session.release();
      endState = hadSession ? 'confirmed' : 'localOnly';
    } catch (_) {
      endState = 'unconfirmed';
      error = '本机动作已取消，设备停止未确认；设备按原有断线/租约规则处理。';
      issueCode = 'releaseUnconfirmed';
    }
    try {
      await session.disconnect();
    } catch (_) {
      endState = 'unconfirmed';
      error = '本机动作已取消，断开未确认；请检查连接和设备状态。';
      issueCode = 'releaseUnconfirmed';
    }
    connection = 'disconnected';
    target = null;
    _notify();
  }

  Future<void> dispose() async {
    await disconnect();
    await _subscription.cancel();
    await session.dispose();
    _disposed = true;
    await _updates.close();
  }
}

extension on Stopwatch {
  Duration elapsedGetter() => elapsed;
}
