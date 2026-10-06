import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:satori_manager/main.dart';
import 'package:satori_manager/runtime/control_client.dart';

Map<String, dynamic> scanState({
  String phase = 'stopped',
  bool confirmed = true,
  List<Map<String, Object?>> devices = const [],
}) => {
  'connection': phase == 'scanning' ? 'searching' : 'disconnected',
  'mode': 'manual',
  'playback': 'idle',
  'outputAuthorized': false,
  'discovered': devices,
  'scanDiagnostics': {
    'phase': phase,
    'stopConfirmed': confirmed,
    'canStart': confirmed && phase != 'scanning',
    'elapsedMs': 8000,
    'resultCount': devices.length,
    'endReason': phase == 'stopped' ? 'timeout' : null,
    'adapterStatus': 'ready',
  },
};
const deviceA = {'id': 'synthetic-a', 'name': '觉瞳 A', 'rssi': -60};
const deviceB = {'id': 'synthetic-b', 'name': '觉瞳 B', 'rssi': -45};

class ScanClient extends ControlClient {
  ScanClient(super.initial) : super.preview();
  final commands = <Map<String, Object?>>[];
  Future<void> Function(String op)? action;
  void update(Map<String, dynamic> next) {
    state = next;
    notifyListeners();
  }

  @override
  Future<void> send(String op, [Map<String, Object?> args = const {}]) async {
    commands.add({'op': op, ...args});
    await action?.call(op);
  }
}

Future<void> settings(WidgetTester tester, ScanClient client) async {
  await tester.pumpWidget(SatoriApp(previewClient: client));
  await tester.tap(find.text('设置'));
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  testWidgets('live results never select until a manual tap and select once', (
    tester,
  ) async {
    final client = ScanClient(
      scanState(phase: 'scanning', confirmed: false, devices: [deviceA]),
    );
    await settings(tester, client);
    expect(client.commands, isEmpty);
    client.update(
      scanState(
        phase: 'scanning',
        confirmed: false,
        devices: [deviceA, deviceB],
      ),
    );
    await tester.pump();
    expect(find.text('觉瞳 B'), findsOneWidget);
    expect(client.commands, isEmpty);
    final selected = Completer<void>();
    client.action = (op) async {
      if (op == 'select') await selected.future;
    };
    final button = find.byKey(const ValueKey('discover-device-synthetic-b'));
    await tapVisible(tester, button);
    await tester.tap(button);
    await tester.pump();
    expect(client.commands, [
      {'op': 'select', 'deviceId': 'synthetic-b'},
    ]);
    expect(find.textContaining('可能按既有设置启用动作'), findsOneWidget);
    selected.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'empty finished scan explains absence and permits explicit retry',
    (tester) async {
      final client = ScanClient(scanState());
      await settings(tester, client);
      expect(find.textContaining('本次没有发现设备'), findsOneWidget);
      await tapVisible(tester, find.text('重新搜索'));
      expect(client.commands, [
        {'op': 'discover'},
      ]);
    },
  );

  testWidgets(
    'stop unknown blocks rescan and selection but permits stop and session ending',
    (tester) async {
      final client = ScanClient(
        scanState(phase: 'stopUnknown', confirmed: false, devices: [deviceA]),
      );
      await settings(tester, client);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('discover-device-synthetic-a')),
            )
            .onPressed,
        isNull,
      );
      await tapVisible(tester, find.text('重新搜索'));
      expect(client.commands, isEmpty);
      await tapVisible(tester, find.text('再次确认停止搜索'));
      expect(client.commands, [
        {'op': 'stopScan'},
      ]);
      await tapVisible(tester, find.text('结束后台会话'));
      expect(client.commands.last['op'], 'disconnect');
      expect(find.textContaining('搜索停止未确认'), findsWidgets);
    },
  );

  testWidgets(
    'cancel remains available while discovery acknowledgement is pending',
    (tester) async {
      final client = ScanClient(scanState());
      final discovery = Completer<void>();
      client.action = (op) async {
        if (op == 'discover') {
          client.update(scanState(phase: 'scanning', confirmed: false));
          await discovery.future;
        }
      };
      await settings(tester, client);
      await tapVisible(tester, find.text('重新搜索'));
      await tapVisible(tester, find.text('取消搜索'));
      expect(client.commands.map((v) => v['op']), ['discover', 'stopScan']);
      discovery.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'scan failure has explicit retry and exposes structured diagnostics',
    (tester) async {
      final client = ScanClient(scanState(phase: 'failed'));
      client.action = (_) async => throw StateError('synthetic scan failure');
      await settings(tester, client);
      expect(find.textContaining('搜索失败'), findsWidgets);
      await tapVisible(tester, find.text('重新搜索'));
      await tester.pumpAndSettle();
      client.action = null;
      await tapVisible(tester, find.text('重新搜索'));
      expect(client.commands.where((v) => v['op'] == 'discover').length, 2);
      await tapVisible(tester, find.text('扫描诊断'));
      await tester.pumpAndSettle();
      expect(find.text('failed'), findsOneWidget);
      expect(find.text('8.0 秒'), findsOneWidget);
      expect(find.text('结果计数（含重复广播）'), findsOneWidget);
      expect(find.text('结束原因'), findsOneWidget);
      expect(find.text('蓝牙适配器'), findsOneWidget);
      expect(find.text('快照新鲜度'), findsOneWidget);
    },
  );

  testWidgets(
    'connection information and authentication have distinct labels',
    (tester) async {
      final client = ScanClient({
        ...scanState(),
        'connection': 'connecting',
        'sessionPhase': 'reading',
      });
      await settings(tester, client);
      expect(find.text('正在读取设备信息并验证连接'), findsWidgets);
      client.update({
        ...scanState(),
        'connection': 'connecting',
        'sessionPhase': 'claiming',
      });
      await tester.pump();
      expect(find.text('正在认证并申请设备控制'), findsWidgets);
    },
  );

  testWidgets(
    'replacing client discards a late old request failure and never auto selects',
    (tester) async {
      final old = ScanClient(
        scanState(phase: 'scanning', confirmed: false, devices: [deviceA]),
      );
      final pending = Completer<void>();
      old.action = (_) => pending.future;
      await settings(tester, old);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('discover-device-synthetic-a')),
      );
      final fresh = ScanClient(scanState(devices: [deviceB]));
      await tester.pumpWidget(SatoriApp(previewClient: fresh));
      await tester.pump();
      pending.completeError(StateError('late old failure'));
      await tester.pumpAndSettle();
      expect(fresh.commands, isEmpty);
      expect(find.textContaining('late old failure'), findsNothing);
      expect(find.text('觉瞳 B'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('failed session ending never reports confirmed stop', (
    tester,
  ) async {
    final client = ScanClient(
      scanState(phase: 'stopUnknown', confirmed: false),
    );
    client.action = (_) async => throw StateError('scan stop not confirmed');
    await settings(tester, client);
    await tapVisible(tester, find.text('结束后台会话'));
    await tester.pumpAndSettle();
    expect(find.textContaining('结束请求已确认'), findsNothing);
    expect(find.textContaining('scan stop not confirmed'), findsWidgets);
    expect(find.textContaining('搜索停止未确认'), findsWidgets);
  });

  testWidgets(
    'native cancellation error and vanished background require whole app restart',
    (tester) async {
      final client = ScanClient(
        scanState(phase: 'stopUnknown', confirmed: false),
      );
      for (final extra in [
        {'errorType': 'cancelError'},
        {'endReason': 'backgroundNotRunning'},
      ]) {
        client.update({
          ...scanState(phase: 'stopUnknown', confirmed: false),
          'scanDiagnostics': {
            ...scanState(
                  phase: 'stopUnknown',
                  confirmed: false,
                )['scanDiagnostics']
                as Map,
            ...extra,
          },
        });
        await settings(tester, client);
        expect(find.textContaining('停止整个应用后重新打开'), findsOneWidget);
        final label = find.text('停止未确认，需结束整个应用');
        await tapVisible(tester, label);
        expect(client.commands, isEmpty);
        expect(find.text('再次确认停止搜索'), findsNothing);
      }
    },
  );

  testWidgets(
    'diagnostics distinguish stale snapshot and duplicate advertisements',
    (tester) async {
      final client = ScanClient(scanState(devices: [deviceA]));
      client.lastSnapshotAt = DateTime.now();
      client.state['scanDiagnostics']['resultCount'] = 8;
      await settings(tester, client);
      await tapVisible(tester, find.text('扫描诊断'));
      await tester.pumpAndSettle();
      expect(find.textContaining('最近快照'), findsOneWidget);
      client.lastSnapshotAt = DateTime.now().subtract(
        const Duration(seconds: 30),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('历史快照'), findsOneWidget);
      expect(find.text('结果计数（含重复广播）'), findsOneWidget);
      expect(find.text('列表设备数'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    },
  );
}
