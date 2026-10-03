import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:satori_manager/core/ble_protocol.dart';
import 'package:satori_manager/core/control_engine.dart';
import 'package:satori_manager/core/device_session.dart';
import 'package:satori_manager/core/ota_window.dart';
import 'package:satori_manager/infrastructure/fake_ble_link.dart';

class WindowLink extends FakeBleLink {
  bool extension = true, policyReady = true, neverAck = false;
  bool disconnectOnHalt = false;
  Completer<List<int>>? nextRead;
  int state = 0, ack = 0, window = 0, remaining = 0;
  int openCount = 0, staleReads = 0, failConnects = 0;
  final otaWrites = <List<int>>[];
  Future<void>? writeWait;
  List<int> status() {
    final ssid = state == 2 || state == 3 ? 'Satori-maint' : '';
    final pass = state == 2 || state == 3 ? 'temporary-test-password' : '';
    final b = List<int>.filled(18, 0);
    b[0] = 1;
    b[1] = state;
    b[2] = policyReady ? 0 : 2;
    for (final entry in [(4, ack), (8, window), (12, remaining)]) {
      for (var i = 0; i < 4; i++) {
        b[entry.$1 + i] = (entry.$2 >> (8 * i)) & 255;
      }
    }
    b[16] = ssid.length;
    b[17] = pass.length;
    return [...b, ...ssid.codeUnits, ...pass.codeUnits];
  }

  @override
  Future<void> connect(String id) async {
    if (failConnects > 0) {
      failConnects--;
      throw StateError('Synthetic reconnect failure');
    }
    await super.connect(id);
  }

  @override
  Future<List<int>> read(String uuid) async {
    if (uuid != OtaWindowStatus.uuid) return super.read(uuid);
    if (!extension) throw StateError('Missing optional extension');
    if (nextRead != null) {
      final pending = nextRead!;
      nextRead = null;
      return pending.future;
    }
    final saved = ack;
    if (neverAck || staleReads-- > 0) ack = 0;
    final raw = status();
    ack = saved;
    return raw;
  }

  @override
  Future<void> write(String uuid, List<int> bytes) async {
    if (uuid != OtaWindowStatus.uuid) {
      if (disconnectOnHalt && bytes[1] == BleOpcode.halt.value) {
        await disconnect();
        throw StateError('Link lost while HALT');
      }
      return super.write(uuid, bytes);
    }
    otaWrites.add(List.from(bytes));
    if (writeWait != null) await writeWait;
    int u32(int n) =>
        bytes[n] | bytes[n + 1] << 8 | bytes[n + 2] << 16 | bytes[n + 3] << 24;
    final id = u32(2);
    if (id == ack) return;
    ack = id;
    if (bytes[1] == 1) {
      openCount++;
      state = 2;
      window = 42;
      remaining = 120000;
    } else if (u32(6) == window || state == 0) {
      state = 0;
      remaining = 0;
    }
  }

  int get arms => writes.where((b) => b[1] == BleOpcode.arm.value).length;
}

void main() {
  test('extension codec exact wire and malformed status rejects', () {
    expect(
      OtaWindowStatus.request(open: true, requestId: 0x12345678, windowId: 0),
      [1, 1, 0x78, 0x56, 0x34, 0x12, 0, 0, 0, 0],
    );
    final link = WindowLink()
      ..state = 2
      ..window = 42;
    final raw = link.status();
    expect(OtaWindowStatus.decode(raw).password, 'temporary-test-password');
    for (final corrupt in [
      raw.sublist(1),
      [...raw, 0],
      [...raw]..[3] = 1,
      [...raw]..[1] = 7,
      [...raw]..[2] = 7,
      [...raw]..[18] = 0xff,
    ]) {
      expect(() => OtaWindowStatus.decode(corrupt), throwsFormatException);
    }
    expect(
      () => OtaWindowStatus.request(open: false, requestId: 1, windowId: 0),
      throwsFormatException,
    );
    expect(
      () => OtaWindowStatus.request(open: true, requestId: 0, windowId: 0),
      throwsFormatException,
    );
  });
  test(
    'old firmware remains compatible, missing extension never opens',
    () async {
      final link = WindowLink()..extension = false;
      final session = DeviceSession(link);
      addTearDown(() async {
        await session.dispose();
        await link.dispose();
      });
      await session.connect('fake');
      expect(session.snapshot.deviceInfo?.protocolVersion, '1.2');
      expect(session.otaSupported, isFalse);
      await expectLater(session.changeOtaWindow(true), throwsStateError);
      expect(link.otaWrites, isEmpty);
      await session.arm();
    },
  );
  test(
    'extension exists but unsigned/signing-not-ready policy blocks open',
    () async {
      final link = WindowLink()..policyReady = false;
      final session = DeviceSession(link);
      addTearDown(() async {
        await session.dispose();
        await link.dispose();
      });
      await session.connect('fake');
      expect(session.otaSupported, isTrue);
      expect(session.otaWindow?.signingReady, isFalse);
      await expectLater(session.changeOtaWindow(true), throwsStateError);
      expect(link.otaWrites, isEmpty);
    },
  );
  test(
    'lost read ACK retries identical bytes without extending/opening twice',
    () async {
      final link = WindowLink();
      final session = DeviceSession(
        link,
        commandTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(() async {
        await session.dispose();
        await link.dispose();
      });
      await session.connect('fake');
      await session.halt();
      link.staleReads = 5;
      await session.changeOtaWindow(true);
      expect(link.openCount, 1);
      expect(link.otaWrites.length, greaterThan(1));
      expect(
        link.otaWrites.every(
          (b) => b.toString() == link.otaWrites.first.toString(),
        ),
        isTrue,
      );
      expect(session.otaWindow?.isOpen, isTrue);
      await session.changeOtaWindow(true);
      expect(link.openCount, 1);
      await session.changeOtaWindow(false);
      expect(session.otaWindow?.isClosed, isTrue);
      expect(link.otaWrites.last.sublist(6), [42, 0, 0, 0]);
    },
  );
  test(
    'write accepted without matching ACK never reports command confirmed',
    () async {
      final link = WindowLink();
      final session = DeviceSession(
        link,
        commandTimeout: const Duration(milliseconds: 10),
      );
      addTearDown(() async {
        await session.dispose();
        await link.dispose();
      });
      await session.connect('fake');
      link.neverAck = true;
      await expectLater(session.changeOtaWindow(true), throwsStateError);
      expect(link.openCount, 1);
      expect(link.otaWrites.length, 4);
      expect(session.maintenanceMode, isTrue);
    },
  );
  test(
    'close confirmed then exit uses fresh CLAIM and remains paused after loss',
    () async {
      final link = WindowLink();
      final session = DeviceSession(link);
      final engine = ControlEngine(session, {});
      addTearDown(() async {
        await engine.dispose();
        await link.dispose();
      });
      await engine.connect('fake');
      final arms = link.arms;
      await engine.openOtaWindow();
      expect(engine.outputAuthorized, isFalse);
      expect(session.snapshot.token, 0);
      await expectLater(engine.arm(), throwsStateError);
      await engine.closeOtaWindow();
      await engine.exitOtaMaintenance();
      expect(session.snapshot.token, isNot(0));
      expect(engine.outputAuthorized, isFalse);
      expect(link.arms, arms);
      await link.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 1250));
      expect(link.arms, arms);
      await engine.arm();
      expect(link.arms, arms + 1);
    },
  );
  test(
    'maintenance disconnect never reconnects or replays ARM; committed close rejects',
    () async {
      final link = WindowLink();
      final session = DeviceSession(link);
      final engine = ControlEngine(session, {});
      addTearDown(() async {
        await engine.dispose();
        await link.dispose();
      });
      await engine.connect('fake');
      await engine.openOtaWindow();
      final arms = link.arms;
      link.state = 5;
      await session.refreshOtaWindow();
      final count = link.otaWrites.length;
      await expectLater(engine.closeOtaWindow(), throwsStateError);
      expect(link.otaWrites.length, count);
      await link.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 1250));
      expect(engine.connection, 'disconnected');
      expect(link.arms, arms);
      expect(engine.snapshot()['otaWindow'], isNull);
      expect(engine.otaNotice, contains('状态未知'));
      await expectLater(engine.exitOtaMaintenance(), throwsStateError);
    },
  );
  test(
    'disconnect during open rejects late completion without stale credentials',
    () async {
      final link = WindowLink();
      final session = DeviceSession(link);
      addTearDown(() async {
        await session.dispose();
        await link.dispose();
      });
      await session.connect('fake');
      final pending = Completer<void>();
      link.writeWait = pending.future;
      final opening = session.changeOtaWindow(true);
      final expectation = expectLater(opening, throwsStateError);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await link.disconnect();
      pending.complete();
      await expectation;
      expect(session.otaWindow, isNull);
    },
  );
  test(
    'HALT disconnect during entry cannot reconnect/ARM, manual reconnect stays paused',
    () async {
      final link = WindowLink();
      final session = DeviceSession(link);
      final engine = ControlEngine(session, {});
      addTearDown(() async {
        await engine.dispose();
        await link.dispose();
      });
      await engine.connect('fake');
      final arms = link.arms;
      link.disconnectOnHalt = true;
      await expectLater(engine.openOtaWindow(), throwsA(anything));
      await Future<void>.delayed(const Duration(milliseconds: 1250));
      expect(link.arms, arms);
      expect(engine.connection, 'disconnected');
      expect(link.otaWrites, isEmpty);
      link.disconnectOnHalt = false;
      await engine.connect('fake');
      expect(link.arms, arms);
      expect(engine.outputAuthorized, isFalse);
    },
  );
  test(
    'reconnect into an existing window skips CLAIM and permits authenticated close',
    () async {
      final link = WindowLink()
        ..state = 2
        ..window = 42
        ..remaining = 120000;
      final session = DeviceSession(link);
      final engine = ControlEngine(session, {});
      addTearDown(() async {
        await engine.dispose();
        await link.dispose();
      });
      await engine.connect('fake');
      expect(link.writes, isEmpty);
      expect(session.snapshot.token, 0);
      expect(engine.otaMaintenance, isTrue);
      await engine.closeOtaWindow();
      await engine.exitOtaMaintenance();
      expect(session.snapshot.token, isNot(0));
      expect(link.arms, 0);
    },
  );
  test(
    'old-generation pending read cannot suppress a new connection probe',
    () async {
      final link = WindowLink();
      final session = DeviceSession(link);
      addTearDown(() async {
        await session.dispose();
        await link.dispose();
      });
      await session.connect('fake');
      final late = Completer<List<int>>();
      link.nextRead = late;
      final oldRead = session.refreshOtaWindow();
      await Future<void>.delayed(Duration.zero);
      await session.disconnect();
      await session.connect('fake');
      expect(session.otaSupported, isTrue);
      late.complete(link.status());
      await oldRead;
      expect(session.otaSupported, isTrue);
    },
  );
  test(
    'exit pause survives failed first reconnect and successful retry',
    () async {
      final link = WindowLink();
      final session = DeviceSession(link);
      final engine = ControlEngine(session, {});
      addTearDown(() async {
        await engine.dispose();
        await link.dispose();
      });
      await engine.connect('fake');
      final arms = link.arms;
      await engine.openOtaWindow();
      await engine.closeOtaWindow();
      await engine.exitOtaMaintenance();
      link.failConnects = 1;
      await link.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 3500));
      expect(engine.connection, 'connected');
      expect(link.arms, arms);
      expect(engine.outputAuthorized, isFalse);
    },
  );
}
