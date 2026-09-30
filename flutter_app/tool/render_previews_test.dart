import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:satori_manager/main.dart';
import 'package:satori_manager/runtime/control_client.dart';

void main() {
  late final Future<void> fontReady = () async {
    final bytes = await File(
      '/usr/share/fonts/google-noto-sans-cjk-vf-fonts/NotoSansCJK-VF.ttc',
    ).readAsBytes();
    await (FontLoader(
      'Preview CJK',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    final iconBytes = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(iconBytes))).load();
  }();
  final base = <String, dynamic>{
    'runtimeId': 'preview',
    'revision': 1,
    'connection': 'disconnected',
    'mode': 'manual',
    'playback': 'idle',
    'autoRotate': false,
    'autoWink': false,
    'battery': null,
    'batteryAt': null,
    'endpoint': null,
    'discovered': <Map<String, Object>>[],
    'simulators': <Map<String, Object>>[],
    'target': null,
    'outputAuthorized': false,
    'simulator': false,
    'error': null,
  };
  final connected = <String, dynamic>{
    ...base,
    'connection': 'connected',
    'outputAuthorized': true,
    'target': [1500, 1500, 1500],
    'deviceId': 'synthetic-preview',
    'simulator': true,
    'endpoint': {'host': '192.0.2.20', 'port': 8888},
    'battery': 77,
    'batteryAt': DateTime.now().toUtc().toIso8601String(),
    'discovered': [
      {'host': '192.0.2.20', 'port': 8888},
    ],
    'simulators': [
      {'host': '192.0.2.20', 'port': 8888},
    ],
  };
  final screens = <(String, Map<String, dynamic>, int)>[
    ('disconnected', base, 0),
    ('device_setup', base, 2),
    (
      'automatic',
      {...connected, 'autoRotate': true, 'autoWink': true, 'mode': 'auto'},
      0,
    ),
    ('manual', connected, 0),
    ('actions', {...connected, 'playback': 'playing'}, 1),
    ('device', connected, 2),
  ];

  for (final screen in screens) {
    testWidgets('render ${screen.$1}', (tester) async {
      await tester.runAsync(() async => fontReady);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: SatoriApp(
            previewClient: ControlClient.preview(screen.$2),
            previewFontFamily: 'Preview CJK',
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (screen.$3 == 1) {
        await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
        await tester.pumpAndSettle();
      }
      if (screen.$3 == 2) {
        await tester.tap(find.byIcon(Icons.devices_rounded));
        await tester.pumpAndSettle();
      }
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('../build/design_preview/${screen.$1}.png'),
      );
    });
  }

  testWidgets('narrow control and setup pages fit without overflow', (
    tester,
  ) async {
    await tester.runAsync(() async => fontReady);
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      SatoriApp(
        previewClient: ControlClient.preview(connected),
        previewFontFamily: 'Preview CJK',
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Icons.devices_rounded));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
