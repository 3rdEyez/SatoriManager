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
  bool failLanRead = false, failApRead = false;
  bool savedExtension = false, saved = false, failAfterSave = false;
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
    if (uuid == DeviceSession.savedNetworkUuid) {
      if (!savedExtension) throw const BleCharacteristicAbsent();
      return [1, 3, saved ? 1 : 0, 0];
    }
    if (uuid == LanWindowStatus.lanUuid) {
      if (failLanRead) throw StateError('No reply');
      if (!extension) throw const BleCharacteristicAbsent();
      if (state == 1 && --connectingReads <= 0) {
        state = failWifi || failAfterSave ? 6 : 2;
        detail = failWifi ? 2 : 0;
      }
      return status();
    }
    if (uuid == OtaWindowStatus.uuid) {
      if (failApRead) throw StateError('No reply');
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
      if (bytes[0] == 3 && !failWifi) saved = true;
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
  test('explicit temporary remember and saved wire', () {
    List<int> request({bool remember = false, bool saved = false}) =>
        LanWindowStatus.lanRequest(
          open: true,
          requestId: 1,
          windowId: 0,
          ssid: saved ? '' : 'synthetic-net',
          password: saved ? '' : 'synthetic-password',
          rememberNetwork: remember,
          useSavedNetwork: saved,
        );
    expect(request()[0], 1);
    expect(request(remember: true)[0], 3);
    expect(request(saved: true), [2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
    expect(() => request(remember: true, saved: true), throwsFormatException);
  });
  test('optional feature leaves old DeviceInfo compatible', () async {
    for (final present in [false, true]) {
      final link = LanLink()..savedExtension = present;
      final session = DeviceSession(link);
      await session.connect('fake');
      expect(session.supportsSavedNetwork, present);
      expect(session.snapshot.deviceInfo!.capabilities & ~0x1ff, 0);
      if (!present) {
        await expectLater(
          session.changeLanWindow(
            true,
            ssid: 'synthetic-net',
            password: 'synthetic-password',
            rememberNetwork: true,
          ),
          throwsStateError,
        );
        expect(link.requests, isEmpty);
      }
      await session.dispose();
      await link.dispose();
    }
  });
  test('remember and explicitly reopen with no credentials or ARM', () async {
    final link = LanLink()..savedExtension = true;
    final session = DeviceSession(link);
    await session.connect('fake');
    await session.changeLanWindow(
      true,
      ssid: 'synthetic-net',
      password: 'synthetic-password',
      rememberNetwork: true,
    );
    expect(link.requests.single[0], 3);
    expect(session.hasSavedNetwork, isTrue);
    await session.changeLanWindow(false);
    await session.changeLanWindow(true, useSavedNetwork: true);
    expect(link.requests.last.length, 12);
    expect(link.requests.last[0], 2);
    expect(link.arms, 0);
    await session.dispose();
    await link.dispose();
  });
  test('temporary network does not set saved metadata', () async {
    final link = LanLink()..savedExtension = true;
    final session = DeviceSession(link);
    await session.connect('fake');
    await session.changeLanWindow(
      true,
      ssid: 'synthetic-net',
      password: 'synthetic-password',
    );
    expect(link.saved, isFalse);
    expect(session.hasSavedNetwork, isFalse);
    expect(link.requests.single[0], 1);
    await session.dispose();
    await link.dispose();
  });
  test('saved metadata refreshes after later HTTP failure', () async {
    final link = LanLink()
      ..savedExtension = true
      ..failAfterSave = true;
    final session = DeviceSession(link);
    await session.connect('fake');
    await expectLater(
      session.changeLanWindow(
        true,
        ssid: 'synthetic-net',
        password: 'synthetic-password',
        rememberNetwork: true,
      ),
      throwsStateError,
    );
    expect(session.hasSavedNetwork, isTrue);
    expect(link.arms, 0);
    await session.dispose();
    await link.dispose();
  });
  testWidgets('remember choice defaults off and is explicit', (tester) async {
    WifiMaintenanceInput? input;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              input = await showDialog<WifiMaintenanceInput>(
                context: context,
                builder: (_) => const WifiSetupDialog(canRememberNetwork: true),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    await tester.enterText(find.byType(TextField).at(0), 'synthetic-net');
    await tester.enterText(find.byType(TextField).at(1), 'synthetic-password');
    await tester.tap(find.text('记住此网络'));
    await tester.pump();
    await tester.tap(find.text('连接网络并开启维护'));
    await tester.pumpAndSettle();
    expect(input?.rememberNetwork, isTrue);
    expect(find.text('synthetic-password'), findsNothing);
  });

  test(
    'engine snapshots preserve unknown capability and disconnected state',
    () async {
      for (final failAp in [false, true]) {
        final link = LanLink()
          ..failLanRead = true
          ..failApRead = failAp;
        final session = DeviceSession(link);
        final engine = ControlEngine(session, {});
        await engine.connect('fake');
        expect(engine.snapshot()['lanSupported'], isNull);
        expect(engine.snapshot()['otaSupported'], failAp ? isNull : isTrue);
        expect(engine.snapshot()['maintenancePath'], 'unknown');
        expect(engine.outputAuthorized, false);
        expect(
          link.writes.where(
            (b) => b[1] == BleOpcode.claim.value || b[1] == BleOpcode.arm.value,
          ),
          isEmpty,
        );
        await engine.disconnect();
        expect(engine.snapshot()['lanSupported'], isNull);
        expect(engine.snapshot()['otaSupported'], isNull);
        await engine.dispose();
        await link.dispose();
      }
      final link = LanLink()..extension = false;
      final session = DeviceSession(link);
      final engine = ControlEngine(session, {});
      await engine.connect('fake');
      expect(engine.snapshot()['lanSupported'], false);
      expect(engine.snapshot()['otaSupported'], true);
      await engine.dispose();
      await link.dispose();
    },
  );
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
        [...raw]..[3] = 7,
        [...raw, 0],
      ]) {
        expect(() => LanWindowStatus.decode(bad), throwsFormatException);
      }
      final closed = LanLink().status();
      expect(LanWindowStatus.decode(closed).toUiJson()['url'], isNull);
    },
  );
  test(
    'unknown LAN read with AP ClosedBusy never CLAIMs; both unknown stay paused',
    () async {
      for (final both in [false, true]) {
        final link = LanLink()
          ..state = 2
          ..window = 61
          ..failLanRead = true
          ..failApRead = both;
        final session = DeviceSession(link);
        await session.connect('fake');
        expect(session.lanSupported, isNull);
        expect(session.maintenanceMode, isTrue);
        expect(session.maintenancePath, 'unknown');
        expect(
          link.writes.where((b) => b[1] == BleOpcode.claim.value),
          isEmpty,
        );
        await expectLater(session.arm(), throwsStateError);
        await expectLater(session.changeOtaWindow(true), throwsStateError);
        await expectLater(session.changeOtaWindow(false), throwsStateError);
        expect(session.activeMaintenanceWindow, isNull);
        expect(session.maintenancePath, 'unknown');
        expect(link.arms, 0);
        await session.dispose();
        await link.dispose();
      }
    },
  );
  test(
    'connected unknown can reconnect to actual LAN window without ARM',
    () async {
      final link = LanLink()
        ..state = 2
        ..window = 61
        ..failLanRead = true;
      final session = DeviceSession(link);
      final engine = ControlEngine(session, {});
      addTearDown(() async {
        await engine.dispose();
        await link.dispose();
      });
      await engine.connect('fake');
      expect(engine.otaMaintenance, isTrue);
      await expectLater(engine.exitOtaMaintenance(), throwsStateError);
      link.failLanRead = false;
      await engine.reconnectOtaMaintenance();
      expect(session.maintenancePath, 'lan');
      expect(session.lanWindow?.isOpen, isTrue);
      expect(link.arms, 0);
      expect(link.writes.where((b) => b[1] == BleOpcode.claim.value), isEmpty);
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
