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
        'target': null,
        'validChannelMask': 0,
        'battery': null,
        'mode': 'manual',
        'playback': 'idle',
      });
      await tester.pumpWidget(SatoriApp(previewClient: client));
      expect(find.text('开始输出'), findsOneWidget);
      expect(find.byType(JoystickPad), findsNothing);
      expect(find.text('电量未知'), findsOneWidget);
      expect(find.text('技术验证版 · BLE 控制'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.devices_rounded));
      await tester.pumpAndSettle();
      expect(find.text('已下发逻辑值：未知'), findsOneWidget);
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
      expect(find.text('CH1 1300  ·  CH2 1700'), findsOneWidget);
      expect(find.textContaining('μs'), findsNothing);
    },
  );
}
