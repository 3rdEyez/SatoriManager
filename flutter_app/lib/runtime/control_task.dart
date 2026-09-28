import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../core/control_engine.dart';
import '../core/protocol.dart';
import '../infrastructure/udp_transport.dart';

@pragma('vm:entry-point')
void startControlTask() {
  FlutterForegroundTask.setTaskHandler(ControlTask());
}

class ControlTask extends TaskHandler {
  ControlEngine? engine;
  StreamSubscription<Map<String, Object?>>? subscription;
  final List<Object> queued = [];
  String? notificationStatus;

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      final actions = parseActions(
        await rootBundle.loadString('assets/actions/presets.json'),
      );
      final active = ControlEngine(UdpTransport(), actions);
      subscription = active.updates.listen((snapshot) {
        final status = switch (snapshot['connection']) {
          'connected'
              when snapshot['autoRotate'] == true ||
                  snapshot['autoWink'] == true =>
            '自动控制中',
          'connected' =>
            snapshot['playback'] == 'playing' ? '动作播放中' : '已连接，等待操作',
          'reconnecting' => '连接中断，正在恢复',
          'searching' => '正在发现设备',
          'failed' => '连接失败，请返回应用处理',
          _ => '未连接设备',
        };
        if (status != notificationStatus) {
          notificationStatus = status;
          FlutterForegroundTask.updateService(notificationText: status);
        }
        FlutterForegroundTask.sendDataToMain({
          'type': 'snapshot',
          'data': snapshot,
        });
      });
      await active.open();
      engine = active;
      FlutterForegroundTask.sendDataToMain({
        'type': 'snapshot',
        'data': active.snapshot(),
      });
      for (final data in queued) {
        onReceiveData(data);
      }
      queued.clear();
    } catch (error) {
      for (final data in queued) {
        if (data is Map) {
          FlutterForegroundTask.sendDataToMain({
            'type': 'rejected',
            'id': data['id'],
            'message': error.toString(),
          });
        }
      }
      queued.clear();
      FlutterForegroundTask.sendDataToMain({
        'type': 'error',
        'message': error.toString(),
      });
      await FlutterForegroundTask.stopService();
    }
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    final id = data['id'];
    final op = data['op'];
    final active = engine;
    if (active == null) {
      queued.add(data);
      return;
    }
    try {
      switch (op) {
        case 'snapshot':
          break;
        case 'discover':
          active.discover(host: data['host'] as String?);
        case 'select':
          final value = data['endpoint'] as Map;
          active.select(
            Endpoint(value['host'] as String, value['port'] as int),
            isSimulator: data['simulator'] == true,
            profile: data['profile'] == null
                ? null
                : SafetyProfile.fromJson(data['profile'] as Map),
          );
        case 'manual':
          active.setManual(List<num>.from(data['values'] as List));
        case 'rotate':
          active.setAutoRotate(data['enabled'] == true);
        case 'winkAuto':
          active.setAutoWink(data['enabled'] == true);
        case 'play':
          active.play(data['name'] as String);
        case 'stop':
          active.stopMotion();
        case 'disconnect':
          active.disconnect();
        default:
          throw StateError('未知操作 $op');
      }
      FlutterForegroundTask.sendDataToMain({
        'type': 'accepted',
        'id': id,
        'snapshot': active.snapshot(),
      });
    } catch (error) {
      FlutterForegroundTask.sendDataToMain({
        'type': 'rejected',
        'id': id,
        'message': error.toString(),
      });
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop') engine?.stopMotion();
    if (id == 'disconnect') {
      engine?.disconnect();
      FlutterForegroundTask.stopService();
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await subscription?.cancel();
    engine?.dispose();
  }
}
