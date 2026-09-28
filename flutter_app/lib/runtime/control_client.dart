import 'dart:async';
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
    'target': [1500, 1500, 1500],
  };
  String? message;
  bool running = false;
  int _id = 0;
  final Map<int, Completer<void>> _pending = {};

  ControlClient() {
    FlutterForegroundTask.addTaskDataCallback(_receive);
    restore();
  }

  ControlClient.preview(Map<String, dynamic> initial) {
    preview = true;
    state = initial;
  }

  Future<void> restore() async {
    if (preview) return;
    try {
      running = await FlutterForegroundTask.isRunningService;
      notifyListeners();
      if (running) await send('snapshot');
    } catch (error) {
      message = error.toString();
      notifyListeners();
    }
  }

  void _receive(Object data) {
    if (data is! Map) return;
    if (data['type'] == 'snapshot' || data['type'] == 'accepted') {
      final raw = data['data'] ?? data['snapshot'];
      if (raw is Map) {
        final incoming = Map<String, dynamic>.from(raw);
        if (incoming['runtimeId'] != state['runtimeId'] ||
            (incoming['revision'] as int? ?? 0) >=
                (state['revision'] as int? ?? 0)) {
          state = incoming;
          notifyListeners();
        }
      }
    }
    if (data['type'] == 'error' || data['type'] == 'rejected') {
      message = data['message']?.toString();
      notifyListeners();
    }
    final id = data['id'];
    if (id is int && _pending.containsKey(id)) {
      final pending = _pending.remove(id)!;
      if (data['type'] == 'rejected') {
        pending.completeError(StateError(data['message'].toString()));
      } else {
        pending.complete();
      }
    }
  }

  Future<void> start() async {
    if (await FlutterForegroundTask.isRunningService) {
      running = true;
      return;
    }
    final result = await FlutterForegroundTask.startService(
      serviceId: 8889,
      notificationTitle: '觉瞳控制会话',
      notificationText: '连接与自动控制正在运行',
      notificationButtons: const [
        NotificationButton(id: 'stop', text: '停止动作'),
        NotificationButton(id: 'disconnect', text: '断开'),
      ],
      callback: startControlTask,
    );
    if (result is ServiceRequestFailure) {
      throw StateError('后台服务启动失败：$result');
    }
    running = true;
    notifyListeners();
  }

  Future<void> send(String op, [Map<String, Object?> args = const {}]) async {
    if (!running) await start();
    final id = ++_id;
    final pending = Completer<void>();
    _pending[id] = pending;
    FlutterForegroundTask.sendDataToTask({'id': id, 'op': op, ...args});
    await pending.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('后台任务未响应');
      },
    );
    if (op == 'disconnect') {
      await FlutterForegroundTask.stopService();
      running = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (!preview) FlutterForegroundTask.removeTaskDataCallback(_receive);
    super.dispose();
  }
}
