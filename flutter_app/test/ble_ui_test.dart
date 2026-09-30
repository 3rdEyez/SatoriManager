import 'package:flutter_test/flutter_test.dart';
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
      expect(find.text('安全范围'), findsNothing);
      await tester.tap(find.text('设备详情'));
      await tester.pumpAndSettle();
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
    await tester.tap(find.text('设备详情'));
    await tester.pumpAndSettle();
    expect(find.textContaining('private firmware exception'), findsOneWidget);
  });
}
