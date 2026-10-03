import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:satori_manager/main.dart';
import 'package:satori_manager/joystick_pad.dart';
import 'package:satori_manager/runtime/control_client.dart';

void main() {
  testWidgets(
    'paused device requires explicit ARM and shows no position feedback',
    (tester) async {
      final client = ControlClient.preview({
        'connection': 'connected',
        'deviceId': 'synthetic-test-device',
        'outputAuthorized': false,
        'controlPhase': 'paused',
        'target': null,
        'battery': null,
        'mode': 'manual',
        'playback': 'idle',
      });
      await tester.pumpWidget(SatoriApp(previewClient: client));
      expect(find.text('启用控制'), findsOneWidget);
      expect(find.byType(JoystickPad), findsOneWidget);
      expect(find.text('指令预览'), findsNothing);
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expect(find.text('蓝牙 · BLE'), findsOneWidget);
      expect(find.text('结束拍摄'), findsOneWidget);
      expect(find.text('安全范围'), findsNothing);
      await tester.scrollUntilVisible(find.text('设备详情'), 200);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -180));
      await tester.pumpAndSettle();
      await tester.tap(find.text('设备详情'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('未知（未采样）'), 100);
      expect(find.text('未知（未采样）'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('设备实际姿态未回传'), 100);
      expect(find.text('设备实际姿态未回传'), findsOneWidget);
    },
  );

  testWidgets('active control keeps joystick and omits numeric targets', (
    tester,
  ) async {
    final client = ControlClient.preview({
      'connection': 'connected',
      'deviceId': 'synthetic-test-device',
      'outputAuthorized': true,
      'target': [1300, 1700, 1400],
      'mode': 'manual',
      'playback': 'idle',
    });
    await tester.pumpWidget(SatoriApp(previewClient: client));
    expect(find.byType(JoystickPad), findsOneWidget);
    expect(find.text('方向摇杆'), findsOneWidget);
    expect(find.textContaining('CH1 1300'), findsNothing);
    expect(find.textContaining('μs'), findsNothing);
  });

  testWidgets('configuration error remains short outside device details', (
    tester,
  ) async {
    final client = ControlClient.preview({
      'connection': 'connected',
      'controlPhase': 'configurationError',
      'outputAuthorized': false,
      'target': null,
      'error': 'private firmware exception',
      'mode': 'manual',
    });
    await tester.pumpWidget(SatoriApp(previewClient: client));
    expect(find.text('设备配置异常，暂时无法控制'), findsWidgets);
    expect(find.textContaining('private firmware exception'), findsNothing);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('设备详情'), 200);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设备详情'));
    await tester.pumpAndSettle();
    expect(find.textContaining('private firmware exception'), findsOneWidget);
  });
  testWidgets(
    'upgrade guidance distinguishes old firmware, signing-not-ready and real window',
    (tester) async {
      Future<void> show(Map<String, dynamic> extra) async {
        await tester.pumpWidget(
          SatoriApp(
            key: UniqueKey(),
            previewClient: ControlClient.preview({
              'connection': 'connected',
              'outputAuthorized': false,
              'mode': 'manual',
              'controlPhase': 'paused',
              'playback': 'idle',
              ...extra,
            }),
          ),
        );
        await tester.tap(find.text('设置'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('固件升级'), 180);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -150));
        await tester.pumpAndSettle();
      }

      await show({'otaSupported': false});
      expect(find.text('当前固件不支持无线升级窗口。'), findsOneWidget);
      expect(find.text('开启升级窗口'), findsNothing);
      await show({
        'otaSupported': true,
        'otaWindow': {'state': 0, 'result': 2},
      });
      expect(find.text('签名升级尚未就绪，暂不能开启窗口。'), findsOneWidget);
      await show({
        'otaSupported': true,
        'otaMaintenance': true,
        'otaWindow': {
          'state': 2,
          'result': 0,
          'windowId': 42,
          'remainingMs': 120000,
          'ssid': 'test-maintenance',
          'password': 'synthetic-password',
        },
      });
      await tester.scrollUntilVisible(find.text('test-maintenance'), 150);
      expect(find.text('synthetic-password'), findsOneWidget);
      expect(find.text('http://192.168.4.1/'), findsOneWidget);
      expect(find.textContaining('上传不需要保持蓝牙'), findsOneWidget);
      expect(find.textContaining('升级完成'), findsNothing);
    },
  );
  testWidgets(
    'lost maintenance link has explicit paused reconnect path without credentials',
    (tester) async {
      await tester.pumpWidget(
        SatoriApp(
          previewClient: ControlClient.preview({
            'connection': 'disconnected',
            'outputAuthorized': false,
            'mode': 'manual',
            'controlPhase': 'paused',
            'playback': 'idle',
            'otaMaintenance': true,
            'otaWindow': null,
            'otaNotice': '窗口状态未知',
          }),
        ),
      );
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('重新连接确认窗口状态'), 180);
      expect(find.text('重新连接确认窗口状态'), findsOneWidget);
      expect(find.text('临时密码'), findsNothing);
      expect(find.textContaining('窗口已关闭'), findsNothing);
    },
  );
}
