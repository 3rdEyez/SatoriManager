import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/control_engine.dart';
import '../core/ble_protocol.dart';
import '../core/device_session.dart';
import '../core/protocol.dart';
import '../core/safety_limits.dart';
import '../core/control_status.dart';
import '../infrastructure/reactive_ble_link.dart';
import 'client_generation_guard.dart';

@pragma('vm:entry-point')
void startControlTask() {
  FlutterForegroundTask.setTaskHandler(ControlTask());
}

class ControlTask extends TaskHandler {
  ControlEngine? engine;
  ReactiveBleLink? link;
  StreamSubscription<Map<String, Object?>>? subscription;
  StreamSubscription<dynamic>? scan;
  final List<Map> queued = [];
  final ClientGenerationGuard _clientGuard = ClientGenerationGuard();
  final Map<String, Map<String, Object?>> discovered = {};
  final SharedPreferencesAsync preferences = SharedPreferencesAsync();
  Map<String, dynamic> favorites = {};
  String? notificationStatus;
  bool searching = false;
  bool destroying = false;
  int revision = 0;

  Map<String, Object?> snapshot() => {
    ...?engine?.snapshot(),
    'revision': ++revision,
    if (searching) 'connection': 'searching',
    'discovered': discovered.values.toList(),
    'favorites': favorites,
  };

  void publish() {
    if (destroying || engine == null) return;
    final state = snapshot();
    final display = '觉瞳 · ${controlStatus(state)}';
    if (display != notificationStatus) {
      notificationStatus = display;
      unawaited(FlutterForegroundTask.updateService(notificationText: display));
    }
    FlutterForegroundTask.sendDataToMain({'type': 'snapshot', 'data': state});
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      final saved = await preferences.getString('bleFavorites');
      if (saved != null) {
        try {
          favorites = Map<String, dynamic>.from(jsonDecode(saved) as Map);
        } on FormatException {
          favorites = {};
        }
      }
      final actions = parseActions(
        await rootBundle.loadString('assets/actions/presets.json'),
      );
      final adapter = ReactiveBleLink();
      link = adapter;
      final active = ControlEngine(DeviceSession(adapter), actions);
      engine = active;
      subscription = active.updates.listen((_) => publish());
      publish();
      for (final data in queued) {
        unawaited(handle(data));
      }
      queued.clear();
    } catch (error) {
      for (final data in queued) {
        reject(data, error);
      }
      queued.clear();
      FlutterForegroundTask.sendDataToMain({
        'type': 'error',
        'message': '$error',
      });
      await FlutterForegroundTask.stopService();
    }
  }

  String describeError(Object error) {
    if (error is BleCommandRejected) {
      return switch (error.result) {
        BleResult.notConfigured => '设备尚未配置已验证的启动姿态，输出未启用。请先完成 USB 维护配置。',
        BleResult.notArmed => '输出尚未就绪，请检查安全范围或设备配置。',
        BleResult.notAuthorized => '设备未授权此手机，请检查系统配对与设备绑定。',
        BleResult.badSession => '控制会话已失效，请重新连接；动作不会自动恢复。',
        _ => '设备拒绝操作：${error.result.name}',
      };
    }
    return '$error';
  }

  void reject(Map data, Object error) {
    FlutterForegroundTask.sendDataToMain({
      'type': 'rejected',
      'id': data['id'],
      'clientId': data['clientId'],
      'message': describeError(error),
      if (engine != null) 'snapshot': snapshot(),
    });
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map || destroying) return;
    if (engine == null) {
      // Only retain startup handshakes. Actions must be based on a snapshot
      // from the live engine, and replaying an early command is surprising.
      if (data['op'] != 'snapshot') {
        reject(data, StateError('后台尚未准备好，请同步状态后重试'));
        return;
      }
      if (queued.length >= 32) {
        reject(data, StateError('后台启动队列已满'));
      } else {
        queued.add(data);
      }
      return;
    }
    unawaited(handle(data));
  }

  Future<void> handle(Map data) async {
    final active = engine!;
    try {
      void ensureCurrentClient() {
        final authorization = _clientGuard.authorize(
          data,
          runtimeId: active.runtimeId,
        );
        if (authorization != null) throw StateError(authorization);
      }

      ensureCurrentClient();
      switch (data['op']) {
        case 'snapshot':
          break;
        case 'discover':
          if (active.connection == 'connected' ||
              active.connection == 'connecting' ||
              active.connection == 'reconnecting') {
            throw StateError('请先结束当前会话');
          }
          await scan?.cancel();
          ensureCurrentClient();
          discovered.clear();
          searching = true;
          publish();
          scan = link!.scan().listen(
            (device) {
              discovered[device.id] = {
                'id': device.id,
                'name': device.name,
                'rssi': device.rssi,
              };
              publish();
            },
            onError: (Object e) {
              searching = false;
              active.error = '$e';
              publish();
            },
            onDone: () {
              searching = false;
              publish();
            },
          );
        case 'select':
          await scan?.cancel();
          ensureCurrentClient();
          searching = false;
          final id = data['deviceId'] as String;
          if (!discovered.containsKey(id)) throw StateError('请先搜索并选择设备');
          final saved = favorites[id];
          final expected = saved is Map ? saved['identity'] as String? : null;
          await active.connect(
            id,
            expectedIdentity: expected,
            safetyForIdentity: (identity) async {
              final previous = favorites.values
                  .whereType<Map>()
                  .where((v) => v['identity'] == identity)
                  .firstOrNull;
              return previous?['safety'] is Map
                  ? SafetyLimits.fromJson(previous!['safety'] as Map)
                  : SafetyLimits.builtInSatoriC3;
            },
          );
          final identity = active.session.snapshot.identity;
          // Locate preferences by stable authenticated identity, not the radio address.
          favorites.removeWhere(
            (key, value) =>
                key != id && value is Map && value['identity'] == identity,
          );
          favorites[id] = {
            'identity': identity,
            'name': discovered[id]?['name'],
            if (active.safety != null) 'safety': active.safety!.toJson(),
          };
          await preferences.setString('bleFavorites', jsonEncode(favorites));
        case 'configureSafety':
          await active.configureSafety(
            SafetyLimits.fromJson(data['limits'] as Map),
          );
          final saved = favorites[active.deviceId];
          if (saved is Map) {
            saved['safety'] = active.safety!.toJson();
            await preferences.setString('bleFavorites', jsonEncode(favorites));
          }
        case 'setPairingCode':
          await active.setPairingCode(
            data['code'] as String,
            ensureCurrentClient: ensureCurrentClient,
          );
        case 'openTransfer':
          await active.openTransfer(ensureCurrentClient: ensureCurrentClient);
        case 'cancelTransfer':
          await active.cancelTransfer(ensureCurrentClient: ensureCurrentClient);
        case 'openOtaWindow':
          await active.openOtaWindow(ensureCurrentClient: ensureCurrentClient);
        case 'closeOtaWindow':
          await active.closeOtaWindow(ensureCurrentClient: ensureCurrentClient);
        case 'reconnectOtaMaintenance':
          ensureCurrentClient();
          await active.reconnectOtaMaintenance();
        case 'exitOtaMaintenance':
          ensureCurrentClient();
          await active.exitOtaMaintenance();
        case 'arm':
          await active.arm();
        case 'manual':
          await active.setManual(List<num>.from(data['values'] as List));
        case 'rotate':
          active.setAutoRotate(data['enabled'] == true);
        case 'winkAuto':
          active.setAutoWink(data['enabled'] == true);
        case 'play':
          active.play(data['name'] as String);
        case 'stop':
          await active.stopMotion();
        case 'disconnect':
          await scan?.cancel();
          ensureCurrentClient();
          searching = false;
          await active.disconnect();
        default:
          throw StateError('未知操作 ${data['op']}');
      }
      FlutterForegroundTask.sendDataToMain({
        'type': 'accepted',
        'id': data['id'],
        'clientId': data['clientId'],
        'snapshot': snapshot(),
      });
    } catch (error) {
      // Pairing credentials must not be echoed by plugin exceptions or replies.
      if (data['op'] == 'setPairingCode' ||
          data['op'] == 'openTransfer' ||
          data['op'] == 'cancelTransfer') {
        reject(data, StateError(active.error ?? '配对设置未确认，请检查连接后重试'));
      } else {
        reject(data, error);
      }
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    unawaited(() async {
      try {
        if (id == 'stop') await engine?.stopMotion();
        if (id == 'disconnect') {
          await scan?.cancel();
          searching = false;
          await engine?.disconnect();
          await FlutterForegroundTask.stopService();
        }
      } catch (e) {
        FlutterForegroundTask.sendDataToMain({
          'type': 'error',
          'message': '$e',
        });
      }
    }());
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    destroying = true;
    await scan?.cancel();
    await subscription?.cancel();
    await engine?.dispose();
    await link?.dispose();
  }
}
