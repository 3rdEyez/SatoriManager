import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:satori_manager/core/ble_protocol.dart';
import 'package:satori_manager/core/control_engine.dart';
import 'package:satori_manager/core/device_session.dart';
import 'package:satori_manager/core/safety_limits.dart';
import 'package:satori_manager/infrastructure/fake_ble_link.dart';
import 'package:satori_manager/runtime/client_generation_guard.dart';

void main() {
  for (final operation in [
    'setPairingCode',
    'openTransfer',
    'cancelTransfer',
  ]) {
    test('retired UI cannot finish $operation after delayed HALT', () async {
      final link = FakeBleLink(initialPairingCode: 654321);
      final engine = ControlEngine(DeviceSession(link), {});
      addTearDown(() async {
        await engine.dispose();
        await link.dispose();
      });
      await engine.connect('fake');
      final guard = ClientGenerationGuard();
      guard.authorize({
        'op': 'snapshot',
        'clientId': 'old',
      }, runtimeId: engine.runtimeId);
      final message = {
        'op': operation,
        'clientId': 'old',
        'expectedRuntimeId': engine.runtimeId,
      };
      void ensureCurrent() {
        final failure = guard.authorize(message, runtimeId: engine.runtimeId);
        if (failure != null) throw StateError(failure);
      }

      link.writeDelay = const Duration(milliseconds: 80);
      final future = switch (operation) {
        'setPairingCode' => engine.setPairingCode(
          '987654',
          ensureCurrentClient: ensureCurrent,
        ),
        'openTransfer' => engine.openTransfer(
          ensureCurrentClient: ensureCurrent,
        ),
        _ => engine.cancelTransfer(ensureCurrentClient: ensureCurrent),
      };
      final rejected = expectLater(future, throwsStateError);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      guard.authorize({
        'op': 'snapshot',
        'clientId': 'new',
      }, runtimeId: engine.runtimeId);
      await rejected;
      final management = link.writes
          .map(BleProtocol.decodeControlFrame)
          .where((frame) => frame.opcode >= 8 && frame.opcode <= 10);
      expect(management, isEmpty);
      expect(link.pairingCode, 654321);
      expect(link.transferWindowOpen, isFalse);
      expect(engine.connection, 'connected');
    });
  }

  test(
    'saving owner code pauses output and never publishes the code',
    () async {
      final link = FakeBleLink();
      final session = DeviceSession(link);
      final engine = ControlEngine(session, {});
      addTearDown(() async {
        await engine.dispose();
        await link.dispose();
      });
      await engine.connect(
        'fake',
        limits: SafetyLimits([500, 500, 500], [2500, 2500, 2500]),
      );
      await engine.arm();
      await engine.setPairingCode('006789');
      expect(engine.outputAuthorized, isFalse);
      expect(engine.connection, 'connected');
      expect(link.pairingCode, 6789);
      expect(engine.snapshot().toString(), isNot(contains('006789')));
      expect(engine.snapshot().toString(), isNot(contains('6789')));
      final ops = link.writes
          .map(BleProtocol.decodeControlFrame)
          .map((f) => f.opcode)
          .toList();
      expect(
        ops.indexOf(BleOpcode.halt.value),
        lessThan(ops.indexOf(BleOpcode.setPairingCode.value)),
      );
      await expectLater(engine.setManual([.5, .5, .5]), throwsStateError);
    },
  );

  test('invalid/default code cannot cause a management write', () async {
    final link = FakeBleLink();
    final engine = ControlEngine(DeviceSession(link), {});
    addTearDown(() async {
      await engine.dispose();
      await link.dispose();
    });
    await engine.connect('fake');
    final before = link.writes.length;
    for (final code in ['123456', '12345', '１２３４５６']) {
      await expectLater(engine.setPairingCode(code), throwsFormatException);
    }
    expect(link.writes.length, before);
  });

  test(
    'transfer disconnect is expected and does not schedule reconnect',
    () async {
      final link = FakeBleLink(sharedPairingSupported: false);
      final scheduled = <Duration>[];
      final engine = ControlEngine(
        DeviceSession(link),
        {},
        schedule: (delay, callback) {
          scheduled.add(delay);
          return Timer(delay, callback);
        },
      );
      addTearDown(() async {
        await engine.dispose();
        await link.dispose();
      });
      await engine.connect('fake');
      await engine.setPairingCode('654321');
      await engine.openTransfer();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(engine.connection, 'disconnected');
      expect(engine.outputAuthorized, isFalse);
      expect(engine.target, isNull);
      expect(link.transferWindowOpen, isTrue);
      expect(scheduled, isEmpty);
      expect(engine.pairingNotice, contains('60秒'));
    },
  );
}
