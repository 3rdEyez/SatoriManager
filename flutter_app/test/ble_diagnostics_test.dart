import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:satori_manager/core/ble_diagnostics.dart';
import 'package:satori_manager/core/ble_protocol.dart';
import 'package:satori_manager/core/device_session.dart';
import 'package:satori_manager/infrastructure/fake_ble_link.dart';

class DiagnosticLink extends FakeBleLink {
  DiagnosticLink({
    this.extension = true,
    this.failure = false,
    this.delayed = false,
  });
  final bool extension, failure, delayed;
  int diagnosticReads = 0;
  final pending = Completer<List<int>>();
  static final sample = '0103040178563412090000000200050013020000';
  static List<int> bytes() => [
    for (var i = 0; i < sample.length; i += 2)
      int.parse(sample.substring(i, i + 2), radix: 16),
  ];
  @override
  Future<List<int>> read(String uuid) async {
    if (uuid == BleDiagnostics.uuid) {
      diagnosticReads++;
      if (failure) throw StateError('Absent characteristic');
      if (delayed) return pending.future;
      return bytes();
    }
    final value = await super.read(uuid);
    if (uuid == BleProtocol.deviceInfoUuid && extension) value[4] = 3;
    return value;
  }
}

void main() {
  test(
    'diagnostic vector matches firmware, reserved/unknown fields fail closed',
    () {
      final d = BleDiagnostics.decode(DiagnosticLink.bytes());
      expect(d.lastStop, 4);
      expect(d.faults, 1);
      expect(d.uptimeSeconds, 0x12345678);
      expect(d.disconnectCount, 9);
      expect(d.leaseExpiryCount, 2);
      expect(d.notificationFailureCount, 5);
      expect(d.lastGapReason, 0x213);
      for (final index in [0, 2, 3, 18, 19]) {
        final invalid = DiagnosticLink.bytes()..[index] = 255;
        expect(() => BleDiagnostics.decode(invalid), throwsFormatException);
      }
    },
  );

  test(
    'old firmware connects without optional reads or synthetic battery',
    () async {
      final link = DiagnosticLink(extension: false);
      final session = DeviceSession(link);
      addTearDown(() async {
        await session.disconnect();
        await session.dispose();
        await link.dispose();
      });
      await session.connect('fake');
      expect(link.diagnosticReads, 0);
      expect(session.snapshot.diagnostics, isNull);
      expect(session.snapshot.state!.batteryPercent, isNull);
    },
  );

  test(
    'new firmware diagnostics do not block ARM; absent extension is harmless',
    () async {
      for (final failure in [false, true]) {
        final link = DiagnosticLink(failure: failure);
        final session = DeviceSession(link);
        await session.connect('fake');
        await session.arm();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(session.snapshot.isArmed, true);
        expect(session.snapshot.diagnostics != null, !failure);
        expect(session.snapshot.lastError, isNull);
        await session.disconnect();
        await session.dispose();
        await link.dispose();
      }
    },
  );

  test(
    'late diagnostic read after disconnect cannot populate another session',
    () async {
      final link = DiagnosticLink(delayed: true);
      final session = DeviceSession(link);
      await session.connect('fake');
      await session.disconnect();
      link.pending.complete(DiagnosticLink.bytes());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(session.snapshot.diagnostics, isNull);
      expect(session.snapshot.diagnosticsAt, isNull);
      await session.dispose();
      await link.dispose();
    },
  );
}
