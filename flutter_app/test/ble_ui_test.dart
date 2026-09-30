import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:satori_manager/main.dart';
import 'package:satori_manager/joystick_pad.dart';
import 'package:satori_manager/runtime/control_client.dart';

void main() {
  testWidgets(
    'paired paused device has explicit ARM and no fabricated target controls',
    (tester) async {
      final client = ControlClient.preview({
        'connection': 'connected',
        'deviceId': 'synthetic-test-device',
        'sessionPhase': 'readyPaused',
        'identity': 'synthetic',
        'outputAuthorized': false,
        'controlPhase': 'paused',
        'target': null,
        'validChannelMask': 0,
        'battery': null,
        'mode': 'manual',
        'playback': 'idle',
      });
      await tester.pumpWidget(SatoriApp(previewClient: client));
      expect(find.text('恢复控制'), findsOneWidget);
      expect(find.byType(JoystickPad), findsNothing);
      expect(find.text('电量未知'), findsOneWidget);
      expect(find.text('测试版'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.devices_rounded));
      await tester.pumpAndSettle();
      expect(find.textContaining('已下发逻辑值'), findsNothing);
      await tester.scrollUntilVisible(find.text('诊断信息'), 200);
      await tester.tap(find.text('诊断信息'));
      await tester.pumpAndSettle();
      expect(find.text('已下发逻辑值（控制目标）：未知'), findsOneWidget);
      expect(find.text('实际机械位置：未知'), findsOneWidget);
      expect(find.text('指定 IPv4（可选）'), findsNothing);
    },
  );

  testWidgets(
    'output-authorized controls show logical targets, no microsecond telemetry',
    (tester) async {
      final client = ControlClient.preview({
        'connection': 'connected',
        'deviceId': 'synthetic-test-device',
        'sessionPhase': 'armed',
        'outputAuthorized': true,
        'target': [1300, 1700, 1400],
        'validChannelMask': 7,
        'mode': 'manual',
        'playback': 'idle',
      });
      await tester.pumpWidget(SatoriApp(previewClient: client));
      expect(find.byType(JoystickPad), findsOneWidget);
      expect(find.text('方向'), findsOneWidget);
      expect(find.textContaining('CH1 1300'), findsNothing);
      expect(find.textContaining('μs'), findsNothing);
    },
  );

  testWidgets('configuration failure is short outside diagnostics', (
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
    expect(find.text('查看详情'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.devices_rounded));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('诊断信息'), 200);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('诊断信息'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('private firmware exception'),
      200,
    );
    expect(find.textContaining('private firmware exception'), findsOneWidget);
  });
}
