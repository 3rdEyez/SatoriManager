import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:satori_manager/core/ble_protocol.dart';
import 'package:satori_manager/core/control_engine.dart';
import 'package:satori_manager/core/device_session.dart';
import 'package:satori_manager/core/lan_window.dart';
import 'package:satori_manager/core/ota_window.dart';
import 'package:satori_manager/infrastructure/fake_ble_link.dart';
import 'package:satori_manager/wifi_setup_dialog.dart';

class LanLink extends FakeBleLink implements BleLargeWriteLink {
  bool extension = true, ready = true, rejectMtu = false, failWifi = false;
  int state = 0, ack = 0, window = 0, detail = 0, connectingReads = 0;
  final requests = <List<int>>[];
  final largeWrites = <int>[];
  static final testToken = 'ab' * 16;
  List<int> status() {
    final open = state == 2 || state == 3;
    final b = List<int>.filled(24, 0);
    b[0] = 1;
    b[1] = state;
    b[2] = ready ? 0 : 2;
    b[3] = detail;
    for (final pair in [(4, ack), (8, window), (12, 120000)]) {
      for (var i = 0; i < 4; i++) {
        b[pair.$1 + i] = (pair.$2 >> (8 * i)) & 255;
      }
    }
    if (open) {
      b.setRange(16, 20, [192, 168, 1, 99]);
      b[20] = 32;
    }
    return [...b, if (open) ...testToken.codeUnits];
  }

  @override
  Future<void> prepareLargeWrite(int length) async {
    largeWrites.add(length);
    if (rejectMtu) throw StateError('Insufficient MTU');
  }

  @override
  Future<List<int>> read(String uuid) async {
    if (uuid == LanWindowStatus.lanUuid) {
      if (!extension) throw StateError('Optional absent');
      if (state == 1 && --connectingReads <= 0) {
        state = failWifi ? 6 : 2;
        detail = failWifi ? 2 : 0;
      }
      return status();
    }
    if (uuid == OtaWindowStatus.uuid) {
      final b = List<int>.filled(18, 0);
      b[0] = 1;
      b[2] = state == 0 ? 0 : 1;
      return b;
    }
    return super.read(uuid);
  }

  @override
  Future<void> write(String uuid, List<int> bytes) async {
    if (uuid != LanWindowStatus.lanUuid) return super.write(uuid, bytes);
    requests.add(List.from(bytes));
    int u32(int n) =>
        bytes[n] | bytes[n + 1] << 8 | bytes[n + 2] << 16 | bytes[n + 3] << 24;
    if (ack == u32(2)) return;
    ack = u32(2);
    if (bytes[1] == 1) {
      state = 1;
      window = 61;
      connectingReads = 3;
    } else {
      state = 0;
      detail = 0;
    }
  }

  int get arms => writes.where((b) => b[1] == BleOpcode.arm.value).length;
}

void main() {
  test('UTF8 SSID bytes and ASCII WPA2 password validate exact request', () {
    final wire = LanWindowStatus.lanRequest(
      open: true,
      requestId: 0x12345678,
      windowId: 0,
      ssid: '网络',
      password: 'synthetic-password',
    );
    expect(wire.sublist(0, 10), [1, 1, 0x78, 0x56, 0x34, 0x12, 0, 0, 0, 0]);
    expect(wire[10], 6);
    expect(utf8.decode(wire.sublist(12, 18)), '网络');
    expect(
      LanWindowStatus.lanRequest(
        open: true,
        requestId: 1,
        windowId: 0,
        ssid: 's' * 32,
        password: 'p' * 63,
      ).length,
      107,
    );
    for (final pair in [
      ('', 'abcdefgh'),
      ('界' * 11, 'abcdefgh'),
      ('s', '短密码'),
      ('s', 'a' * 7),
      ('s', 'a' * 64),
      ('s', 'abcdefgh\n'),
      ('s\u0000', 'abcdefgh'),
      ('s\n', 'abcdefgh'),
      ('s\u007f', 'abcdefgh'),
    ]) {
      expect(
        () => LanWindowStatus.lanRequest(
          open: true,
          requestId: 1,
          windowId: 0,
          ssid: pair.$1,
          password: pair.$2,
        ),
        throwsFormatException,
      );
    }
    expect(
      LanWindowStatus.lanRequest(open: false, requestId: 2, windowId: 61),
      [1, 2, 2, 0, 0, 0, 61, 0, 0, 0, 0, 0],
    );
    expect(
      () => LanWindowStatus.lanRequest(
        open: false,
        requestId: 2,
        windowId: 61,
        password: 'abcdefgh',
      ),
      throwsFormatException,
    );
  });
  test(
    'ready status requires actual IP and token; public snapshot never includes token',
    () {
      final link = LanLink()
        ..state = 2
        ..window = 61;
      final raw = link.status(), parsed = LanWindowStatus.decode(link.status());
      expect(parsed.url, 'http://192.168.1.99/');
      expect(parsed.uploadToken, LanLink.testToken);
      expect(jsonEncode(parsed.toUiJson()), isNot(contains(LanLink.testToken)));
      for (final bad in [
        raw.sublist(0, 24),
        [...raw]..[16] = 0,
        [...raw]..[16] = 239,
        [...raw]..[21] = 1,
        [...raw]..[24] = 0x41,
        [...raw]..[3] = 5,
        [...raw, 0],
      ]) {
        expect(() => LanWindowStatus.decode(bad), throwsFormatException);
      }
      final closed = LanLink().status();
      expect(LanWindowStatus.decode(closed).toUiJson()['url'], isNull);
    },
  );
  test(
    'missing LAN extension is unsupported without affecting AP or old control',
    () async {
      final link = LanLink()..extension = false;
      final session = DeviceSession(link);
      addTearDown(() async {
        await session.dispose();
        await link.dispose();
      });
      await session.connect('fake');
      expect(session.lanSupported, isFalse);
      await expectLater(
        session.changeLanWindow(true, ssid: 's', password: 'abcdefgh'),
        throwsStateError,
      );
      expect(link.requests, isEmpty);
      expect(session.otaSupported, isTrue);
      await session.arm();
    },
  );
  test(
    'LAN connecting is polled to real Ready, credentials omitted from snapshots, exit paused',
    () async {
      final link = LanLink();
      final session = DeviceSession(link);
      final engine = ControlEngine(session, {});
      addTearDown(() async {
        await engine.dispose();
        await link.dispose();
      });
      await engine.connect('fake');
      final arms = link.arms;
      final opening = engine.openOtaWindow(
        lan: true,
        ssid: 'private-network',
        password: 'private-password',
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(engine.outputAuthorized, isFalse);
      expect(link.state, 1);
      await opening;
      expect(session.lanWindow?.isOpen, isTrue);
      expect(link.requests.length, 1);
      await expectLater(session.changeOtaWindow(true), throwsStateError);
      expect(session.maintenancePath, 'lan');
      expect(session.activeMaintenanceWindow?.isOpen, isTrue);
      expect(link.largeWrites.single, greaterThan(20));
      final snapshot = jsonEncode(engine.snapshot());
      for (final secret in [
        'private-network',
        'private-password',
        LanLink.testToken,
      ]) {
        expect(snapshot, isNot(contains(secret)));
      }
      expect(engine.snapshot()['maintenancePath'], 'lan');
      await engine.closeOtaWindow();
      expect(link.requests.last[1], 2);
      await engine.exitOtaMaintenance();
      expect(link.arms, arms);
      expect(engine.outputAuthorized, isFalse);
    },
  );
  test(
    'low MTU fails before credential write and keeps maintenance stop lock',
    () async {
      final link = LanLink()..rejectMtu = true;
      final session = DeviceSession(link);
      final engine = ControlEngine(session, {});
      addTearDown(() async {
        await engine.dispose();
        await link.dispose();
      });
      await engine.connect('fake');
      final arms = link.arms;
      await expectLater(
        engine.openOtaWindow(
          lan: true,
          ssid: 's',
          password: 'private-password',
        ),
        throwsStateError,
      );
      expect(link.requests, isEmpty);
      expect(engine.outputAuthorized, isFalse);
      await expectLater(engine.arm(), throwsStateError);
      expect(link.arms, arms);
    },
  );
  test('structured connection timeout cannot be reported as Ready', () async {
    final link = LanLink()..failWifi = true;
    final session = DeviceSession(link);
    final engine = ControlEngine(session, {});
    addTearDown(() async {
      await engine.dispose();
      await link.dispose();
    });
    await engine.connect('fake');
    await expectLater(
      engine.openOtaWindow(lan: true, ssid: 's', password: 'private-password'),
      throwsStateError,
    );
    expect(session.lanWindow?.state, 6);
    expect(session.lanWindow?.detail, 2);
    expect(engine.otaNotice, isNot(contains('已确认连接')));
    expect(engine.outputAuthorized, isFalse);
  });
  test(
    'already-open LAN reconnect skips CLAIM and controls until confirmed close',
    () async {
      final link = LanLink()
        ..state = 2
        ..window = 61;
      final session = DeviceSession(link);
      final engine = ControlEngine(session, {});
      addTearDown(() async {
        await engine.dispose();
        await link.dispose();
      });
      await engine.connect('fake');
      expect(link.writes, isEmpty);
      expect(session.maintenancePath, 'lan');
      await expectLater(engine.arm(), throwsStateError);
      await engine.closeOtaWindow();
      await engine.exitOtaMaintenance();
      expect(session.snapshot.token, isNot(0));
      expect(link.arms, 0);
    },
  );
  testWidgets(
    'Wi-Fi form is RAM-only, password obscured, no saved password or save option',
    (tester) async {
      WifiMaintenanceInput? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<WifiMaintenanceInput>(
                  context: context,
                  builder: (_) => const WifiSetupDialog(),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('不保存到手机'), findsOneWidget);
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(fields[1].obscureText, isTrue);
      expect(fields[1].controller?.text, '');
      expect(find.byType(Checkbox), findsNothing);
      await tester.enterText(find.byType(TextField).first, 's');
      await tester.enterText(find.byType(TextField).last, 'short');
      await tester.tap(find.text('连接网络并开启维护'));
      await tester.pumpAndSettle();
      expect(find.textContaining('SSID须为'), findsOneWidget);
      expect(result, isNull);
      await tester.enterText(find.byType(TextField).last, 'synthetic-password');
      await tester.tap(find.text('连接网络并开启维护'));
      await tester.pumpAndSettle();
      expect(result?.ssid, 's');
      expect(result?.password, 'synthetic-password');
      expect(find.byType(WifiSetupDialog), findsNothing);
    },
  );
}
