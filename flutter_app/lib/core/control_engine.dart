import 'dart:async';
import 'dart:math';
import '../infrastructure/udp_transport.dart';
import 'protocol.dart';

typedef Clock = DateTime Function();
typedef Schedule = Timer Function(Duration delay, void Function() callback);

class ControlEngine {
  ControlEngine(
    this.transport,
    this.actions, {
    Clock? clock,
    Schedule? schedule,
    Random? random,
  }) : now = clock ?? DateTime.now,
       later = schedule ?? Timer.new,
       random = random ?? Random();
  final Transport transport;
  final Map<String, List<ActionFrame>> actions;
  final Clock now;
  final Schedule later;
  final Random random;
  final _updates = StreamController<Map<String, Object?>>.broadcast();
  Stream<Map<String, Object?>> get updates => _updates.stream;
  final String runtimeId = DateTime.now().microsecondsSinceEpoch.toRadixString(
    36,
  );
  int revision = 0;
  String connection = 'disconnected';
  String mode = 'manual';
  String playback = 'idle';
  bool autoRotate = false;
  bool autoWink = false;
  int? battery;
  DateTime? batteryAt;
  Endpoint? endpoint;
  Endpoint? discoveryTarget;
  SafetyProfile? safety;
  bool simulator = false;
  List<int> target = [1500, 1500, 1500];
  final List<Endpoint> discovered = [];
  final List<Endpoint> simulators = [];
  final Map<Endpoint, int?> discoveryBattery = {};
  String? error;
  DateTime? _lastReply;
  Timer? _heartbeat;
  Timer? _discoveryTimer;
  Timer? _reconnect;
  Timer? _rotate;
  Timer? _wink;
  Timer? _frame;
  int _epoch = 0;
  int _attempts = 0;
  bool _opened = false;

  Map<String, Object?> snapshot() => {
    'runtimeId': runtimeId,
    'revision': revision,
    'connection': connection,
    'mode': mode,
    'playback': playback,
    'autoRotate': autoRotate,
    'autoWink': autoWink,
    'battery': battery,
    'batteryAt': batteryAt?.toUtc().toIso8601String(),
    'endpoint': endpoint?.toJson(),
    'discovered': discovered.map((v) => v.toJson()).toList(),
    'simulators': simulators.map((v) => v.toJson()).toList(),
    'target': target,
    'simulator': simulator,
    'error': error,
  };

  void _notify() {
    revision++;
    _updates.add(snapshot());
  }

  Future<void> open() async {
    if (_opened) return;
    await transport.open(_onPacket, (message) {
      error = message;
      _notify();
    });
    _opened = true;
    _heartbeat = later(const Duration(seconds: 20), _heartbeatTick);
    _notify();
  }

  void discover({String? host}) {
    if (!_opened) throw StateError('先启动会话');
    if (connection == 'connected') return;
    discovered.clear();
    simulators.clear();
    discoveryBattery.clear();
    discoveryTarget = host == null ? null : Endpoint(host, 8888);
    connection = 'searching';
    error = null;
    _notify();
    _discoveryTimer?.cancel();
    _discoveryTimer = later(const Duration(seconds: 5), () {
      if (connection == 'searching') {
        connection = discovered.isEmpty ? 'no_results' : 'found';
        _notify();
      }
    });
    transport.send(
      discoveryTarget ?? const Endpoint('255.255.255.255', 8888),
      Protocol.discovery,
    );
  }

  void select(
    Endpoint selected, {
    SafetyProfile? profile,
    required bool isSimulator,
  }) {
    if (!discovered.contains(selected)) throw StateError('请先发现该端点');
    if (isSimulator && !simulators.contains(selected)) {
      throw StateError('该端点没有模拟器标识，不能启用完整行程');
    }
    _cancelMotion();
    _discoveryTimer?.cancel();
    endpoint = selected;
    safety = profile;
    simulator = isSimulator;
    target = List.of(profile?.initial ?? [1500, 1500, 1500]);
    connection = 'connected';
    mode = 'manual';
    battery = discoveryBattery[selected];
    batteryAt = battery == null ? null : now();
    _lastReply = now();
    _attempts = 0;
    _reconnect?.cancel();
    error = null;
    _notify();
  }

  void _onPacket(Endpoint source, List<int> bytes) {
    final reply = Protocol.parse(bytes);
    if (reply == null) return;
    if (connection == 'searching' && reply.kind == ReplyKind.discovery) {
      if (discoveryTarget != null && source.host != discoveryTarget!.host) {
        return;
      }
      if (!discovered.contains(source)) discovered.add(source);
      if (reply.simulator && !simulators.contains(source)) {
        simulators.add(source);
      }
      discoveryBattery[source] = reply.battery;
      _notify();
      return;
    }
    if (endpoint != source ||
        (connection != 'connected' && connection != 'reconnecting')) {
      return;
    }
    if (reply.kind == ReplyKind.discovery) return;
    _lastReply = now();
    if (reply.battery != null) {
      battery = reply.battery;
      batteryAt = now();
    }
    if (connection == 'reconnecting') {
      connection = 'connected';
      _attempts = 0;
      _reconnect?.cancel();
      error = null;
    }
    if (reply.kind == ReplyKind.mode && reply.mode == 'Sleep') {
      mode = 'sleep';
      _cancelMotion();
    }
    _notify();
  }

  void _heartbeatTick() {
    _heartbeat = later(const Duration(seconds: 20), _heartbeatTick);
    final selected = endpoint;
    if (selected == null) return;
    if (connection == 'connected' &&
        _lastReply != null &&
        now().difference(_lastReply!) >= const Duration(seconds: 60)) {
      _cancelMotion();
      connection = 'reconnecting';
      error = '60 秒未收到设备有效响应';
      _attempts = 0;
      _reconnectTick();
      _notify();
      return;
    }
    if (connection == 'connected') transport.send(selected, Protocol.heartbeat);
  }

  void _reconnectTick() {
    if (connection != 'reconnecting') return;
    if (_attempts >= 5) {
      connection = 'failed';
      error = '原设备恢复失败，请重新发现并选择';
      _notify();
      return;
    }
    _attempts++;
    transport.send(endpoint!, Protocol.heartbeat);
    _reconnect = later(const Duration(seconds: 10), _reconnectTick);
  }

  void _requireControl() {
    if (connection != 'connected') throw StateError('设备未连接');
    if (safety == null) throw StateError('请先填写已确认的安全范围和初始目标');
  }

  void setManual(List<num> proportions) {
    _requireControl();
    if (proportions.length != 3) throw const FormatException('需要三个通道');
    _cancelMotion();
    mode = 'manual';
    final next = [for (final value in proportions) Protocol.proportion(value)];
    _send(next);
  }

  void setAutoRotate(bool enabled) {
    _requireControl();
    _frame?.cancel();
    playback = 'idle';
    _rotate?.cancel();
    autoRotate = enabled;
    mode = enabled ? 'auto' : 'manual';
    _notify();
    if (enabled) _rotateTick();
  }

  void _rotateTick() {
    if (!autoRotate || connection != 'connected') return;
    final next = List<int>.of(target);
    next[0] = (1500 + (random.nextDouble() - .5) * 500).truncate();
    next[1] = (1500 + (random.nextDouble() - .5) * 500).truncate();
    _send(next, smoothMs: 200);
    _rotate = later(const Duration(seconds: 5), _rotateTick);
  }

  void setAutoWink(bool enabled) {
    _requireControl();
    _wink?.cancel();
    autoWink = enabled;
    _notify();
    if (enabled) _wink = later(const Duration(seconds: 5), _winkTick);
  }

  void _winkTick() {
    if (!autoWink || connection != 'connected') return;
    if (playback == 'idle') {
      play(random.nextBool() ? 'wink' : 'wink2', automatic: true);
    }
    _wink = later(const Duration(seconds: 5), _winkTick);
  }

  void play(String name, {bool automatic = false}) {
    _requireControl();
    final frames = actions[name];
    if (frames == null) throw StateError('未知动作 $name');
    if (playback == 'playing') return;
    _frame?.cancel();
    playback = 'playing';
    final epoch = ++_epoch;
    _notify();
    void step(int index) {
      if (epoch != _epoch || connection != 'connected') return;
      if (index >= frames.length) {
        playback = 'idle';
        _notify();
        return;
      }
      final next = List<int>.of(target);
      for (var i = 0; i < 3; i++) {
        if (frames[index].channels[i] != -1) {
          next[i] = Protocol.proportion(frames[index].channels[i]);
        }
      }
      _send(next, smoothMs: 200);
      _frame = later(frames[index].duration, () => step(index + 1));
    }

    step(0);
  }

  void _send(List<int> next, {int? smoothMs}) {
    _requireControl();
    target = safety!.constrain(next);
    transport.send(endpoint!, Protocol.pwm(target, smoothMs: smoothMs));
    _notify();
  }

  void _cancelMotion() {
    ++_epoch;
    _frame?.cancel();
    _rotate?.cancel();
    _wink?.cancel();
    autoRotate = false;
    autoWink = false;
    playback = 'idle';
  }

  void stopMotion() {
    _cancelMotion();
    mode = 'manual';
    _notify();
  }

  void disconnect() {
    _cancelMotion();
    _discoveryTimer?.cancel();
    _reconnect?.cancel();
    if (endpoint != null) {
      try {
        transport.send(endpoint!, Protocol.disconnect);
      } catch (_) {
        /* best effort */
      }
    }
    endpoint = null;
    safety = null;
    connection = 'disconnected';
    mode = 'manual';
    battery = null;
    batteryAt = null;
    _notify();
  }

  void dispose() {
    disconnect();
    _heartbeat?.cancel();
    transport.close();
    _updates.close();
  }
}
