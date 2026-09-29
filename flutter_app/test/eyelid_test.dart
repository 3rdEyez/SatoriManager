import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:satori_manager/main.dart';
import 'package:satori_manager/runtime/control_client.dart';

class EyelidClient extends ControlClient {
  EyelidClient()
    : super.preview({
        'connection': 'connected',
        'deviceId': 'synthetic-device',
        'outputAuthorized': true,
        'target': [1300, 1700, 1500],
        'validChannelMask': 7,
        'mode': 'manual',
        'playback': 'idle',
      });

  final commands = <(String, Map<String, Object?>)>[];

  @override
  Future<void> send(String op, [Map<String, Object?> args = const {}]) async {
    commands.add((op, args));
  }
}

void main() {
  testWidgets('eyelid drag sends before release and flushes final CH3 only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = EyelidClient();
    await tester.pumpWidget(SatoriApp(previewClient: client));
    final slider = find.byKey(const ValueKey('eyelid-slider'));
    await tester.ensureVisible(slider);
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    expect(client.commands, isNotEmpty);
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    final finalValue = tester.widget<Slider>(slider).value;
    final beforeRelease = client.commands.length;
    await gesture.up();
    await tester.pump();
    expect(client.commands.length, greaterThan(beforeRelease));
    expect(client.commands.last.$2['values'], [-1, -1, finalValue]);
    for (final command in client.commands) {
      expect(command.$1, 'manual');
      expect((command.$2['values'] as List).take(2), [-1, -1]);
    }
    expect(finalValue, greaterThan(.5));
  });
}
