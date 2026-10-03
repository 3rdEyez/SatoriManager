import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'control_task.dart';

class ControlClient extends ChangeNotifier {
  bool preview = false;
  Map<String, dynamic> state = {
    'connection': 'disconnected',
    'mode': 'manual',
    'playback': 'idle',
    'autoRotate': false,
    'autoWink': false,
    'discovered': <Object>[],
    'target': null,
    'outputAuthorized': false,
  };
  String? message;
  bool running = false;
  bool _disposed = false;
  Future<void>? _starting;
  Future<void>? _handshaking;
  bool _handshaken = false;
  int _id = 0;
  final String _clientId =
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
  final Map<int, Completer<void>> _pending = {};
  final Map<int, String> _pendingOps = {};
  final Set<String> _retiredRuntimes = {};

  ControlClient() {
    FlutterForegroundTask.addTaskDataCallback(_receive);
    unawaited(restore());
  }
  ControlClient.preview(Map<String, dynamic> initial) {
    preview = true;
    state = initial;
  }
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> restore() async {
    if (preview || _disposed) return;
    try {
      running = await FlutterForegroundTask.isRunningService;
      if (running) {
        _handshaken = false;
        await _establishHandshake();
      } else {
        _handshaken = false;
        final old = state['runtimeId'];
        if (old is String) _retiredRuntimes.add(old);
        state = {
          ...state,
          'runtimeId': null,
          'connection': 'disconnected',
          'outputAuthorized': false,
          'autoRotate': false,
          'autoWink': false,
          'playback': 'idle',
          'target': null,
        };
      }
      _notify();
    } catch (error) {
      message = error.toString();
      _notify();
    }
  }

  void _receive(Object data) {
    if (_disposed || data is! Map) return;
    if (data['clientId'] != null && data['clientId'] != _clientId) return;
    final raw = data['data'] ?? data['snapshot'];
    if (raw is Map) {
      final incoming = Map<String, dynamic>.from(raw);
      final runtime = incoming['runtimeId'];
      if (runtime is! String || _retiredRuntimes.contains(runtime)) return;
      if (runtime != state['runtimeId'] &&
          state['runtimeId'] != null &&
          !(data['clientId'] == _clientId &&
              _pendingOps[data['id']] == 'snapshot')) {
        return;
      }
      if (runtime != state['runtimeId']) {
        final old = state['runtimeId'];
        if (old is String) _retiredRuntimes.add(old);
      }
      if (runtime != state['runtimeId'] ||
          (incoming['revision'] as int? ?? 0) >=
              (state['revision'] as int? ?? 0)) {
        state = incoming;
        _notify();
      }
    }
    if (data['type'] == 'error' || data['type'] == 'rejected') {
      message = data['message']?.toString();
      _notify();
    }
    final id = data['id'];
    if (id is int &&
        data['clientId'] == _clientId &&
        _pending.containsKey(id)) {
      final pending = _pending.remove(id)!;
      if (data['type'] == 'rejected') {
        pending.completeError(StateError(data['message'].toString()));
      } else {
        pending.complete();
      }
    }
  }

  Future<void> start() =>
      _starting ??= _start().whenComplete(() => _starting = null);
  Future<void> _start() async {
    if (await FlutterForegroundTask.isRunningService) {
      running = true;
      await _establishHandshake();
      return;
    }
    _handshaken = false;
    final old = state['runtimeId'];
    if (old is String) _retiredRuntimes.add(old);
    state = {...state, 'runtimeId': null, 'outputAuthorized': false};
    final result = await FlutterForegroundTask.startService(
      serviceId: 8889,
      notificationTitle: '觉瞳 BLE 控制会话',
      notificationText: '正在准备蓝牙连接',
      notificationButtons: const [
        NotificationButton(id: 'stop', text: '暂停控制'),
        NotificationButton(id: 'disconnect', text: '结束拍摄'),
      ],
      callback: startControlTask,
    );
    if (result is ServiceRequestFailure) throw StateError('后台服务启动失败：$result');
    running = true;
    await _establishHandshake();
    _notify();
  }

  Future<void> _establishHandshake() {
    if (_handshaken) return Future<void>.value();
    return _handshaking ??= _sendRequest('snapshot')
        .then((_) {
          _handshaken = true;
        })
        .whenComplete(() => _handshaking = null);
  }

  Future<void> send(String op, [Map<String, Object?> args = const {}]) async {
    if (_disposed) throw StateError('界面已关闭');
    if (!running) {
      if (op == 'stop' || op == 'disconnect') return;
      await start();
    }
    if (op == 'snapshot') {
      _handshaken = false;
      await _establishHandshake();
      return;
    }
    await _establishHandshake();
    await _sendRequest(op, args);
  }

  Future<void> _sendRequest(
    String op, [
    Map<String, Object?> args = const {},
  ]) async {
    if (op != 'snapshot' && state['runtimeId'] is! String) {
      throw StateError('后台会话尚未同步，请刷新状态后重试');
    }
    final id = ++_id;
    final pending = Completer<void>();
    _pending[id] = pending;
    _pendingOps[id] = op;
    message = null;
    FlutterForegroundTask.sendDataToTask({
      'id': id,
      'clientId': _clientId,
      'op': op,
      'expectedRuntimeId': state['runtimeId'],
      ...args,
    });
    try {
      await pending.future.timeout(
        Duration(seconds: op == 'select' ? 120 : 15),
      );
    } on TimeoutException {
      throw TimeoutException('后台操作尚未确认，请刷新状态或断开');
    } finally {
      _pending.remove(id);
      _pendingOps.remove(id);
    }
    if (op == 'disconnect' || op == 'openTransfer') {
      await FlutterForegroundTask.stopService();
      running = false;
      _handshaken = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (!preview) FlutterForegroundTask.removeTaskDataCallback(_receive);
    for (final pending in _pending.values) {
      pending.completeError(StateError('界面已关闭；设备会话仍由后台管理'));
    }
    _pending.clear();
    _pendingOps.clear();
    super.dispose();
  }
}
