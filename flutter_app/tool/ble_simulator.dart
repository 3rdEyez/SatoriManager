// ignore_for_file: avoid_print
import 'dart:io';
import 'package:satori_manager/core/ble_protocol.dart';
import 'package:satori_manager/core/device_session.dart';
import 'package:satori_manager/infrastructure/fake_ble_link.dart';

/// Synthetic, in-memory peer. This program never opens a Bluetooth adapter.
Future<void> main(List<String> args) async {
  if (args.contains('--help')) {
    print(
      'Dart BLE simulation only (no radio/PWM): --drop-first-ack --unconfigured',
    );
    return;
  }
  if (args.any(
    (arg) => !['--drop-first-ack', '--unconfigured'].contains(arg),
  )) {
    throw const FormatException('Unknown option; use --help');
  }
  final unconfigured = args.contains('--unconfigured');
  final link = FakeBleLink(
    configured: !unconfigured,
    dropNextReplies: args.contains('--drop-first-ack') ? 1 : 0,
  );
  final session = DeviceSession(link);
  print('SIMULATOR — synthetic software state only; no BLE hardware or PWM.');
  try {
    await session.connect('synthetic');
    print('CLAIM confirmed; connected and paused; output values unknown.');
    try {
      await session.arm();
    } on BleCommandRejected catch (e) {
      if (unconfigured && e.result == BleResult.notConfigured) {
        print(
          'ARM correctly rejected: NOT_CONFIGURED. Output remains disabled.',
        );
        return;
      }
      rethrow;
    }
    print(
      'ARM confirmed; synthetic startup ${session.snapshot.state!.channels}.',
    );
    await session.setTarget(ch1: 1510, ch2: 1490, ch3: 1500, latestOnly: false);
    print('Synthetic target accepted (not physical arrival).');
    await session.halt();
    print('HALT confirmed; pending movement cancelled.');
    await session.release();
    print('RELEASE confirmed; disconnected. Writes: ${link.writes.length}.');
  } catch (e) {
    stderr.writeln('Simulation failed: $e');
    exitCode = 1;
  } finally {
    await session.disconnect();
    await session.dispose();
    await link.dispose();
  }
}
