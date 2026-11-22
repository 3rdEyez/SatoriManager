// Hardware-only, paused BLE acceptance. Never logs identities or frame values.
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:satori_manager/core/ble_protocol.dart';
import 'package:satori_manager/core/ble_diagnostics.dart';
import 'package:satori_manager/core/device_session.dart';
import 'package:satori_manager/infrastructure/bluez_ble_link.dart';

class _PausedLink implements BleLink {
  final transport = BluezBleLink();
  final reads = <String, int>{};
  final commands = <int, int>{};
  int notifications = 0;
  Map<String, Object?>? firstDiagnostics;
  Map<String, Object?>? latestDiagnostics;

  @override
  Stream<BleLinkState> get connectionState => transport.connectionState;
  @override
  Future<void> connect(String id) => transport.connect(id);
  @override
  Future<void> disconnect() => transport.disconnect();
  @override
  Future<List<int>> read(String uuid) async {
    final value = await transport.read(uuid);
    reads.update(uuid, (count) => count + 1, ifAbsent: () => 1);
    if (uuid == BleDiagnostics.uuid) {
      latestDiagnostics = BleDiagnostics.decode(value).toJson();
      firstDiagnostics ??= latestDiagnostics;
      print(
        jsonEncode({'phase': 'firmware_diagnostics', ...latestDiagnostics!}),
      );
    }
    return value;
  }

  @override
  Future<void> write(String uuid, List<int> value) async {
    // Enforce the safety boundary at the actual transport, even if session
    // policy changes later. ARM, targets and maintenance writes are rejected.
    if (uuid != BleProtocol.controlRxUuid ||
        value.length != 20 ||
        !{1, 3, 4, 5, 6}.contains(value[1])) {
      throw StateError('Acceptance probe blocked a non-paused command');
    }
    await transport.write(uuid, value);
    commands.update(value[1], (count) => count + 1, ifAbsent: () => 1);
  }

  @override
  Stream<List<int>> subscribe(String uuid) =>
      transport.subscribe(uuid).map((v) {
        notifications++;
        return v;
      });
}

void _checkPaused(DeviceSession session) {
  final snapshot = session.snapshot;
  if (snapshot.phase != DeviceSessionPhase.readyPaused ||
      snapshot.state?.controlState != 1 ||
      snapshot.state?.interpolatingChannelMask != 0 ||
      snapshot.lastError != null) {
    throw StateError(
      'Session did not remain healthy and paused: '
      'phase=${snapshot.phase.name}, control=${snapshot.state?.controlState}, '
      'error=${snapshot.lastError}',
    );
  }
}

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    print('Usage: dart run tool/ble_acceptance_probe.dart <known-address>');
    exitCode = 64;
    return;
  }
  final rounds = <Map<String, Object?>>[];
  try {
    for (var round = 1; round <= 3; round++) {
      final link = _PausedLink();
      final session = DeviceSession(link);
      final clock = Stopwatch()..start();
      var disconnected = false;
      var phase = 'connecting';
      print(jsonEncode({'round': round, 'phase': 'connecting'}));
      try {
        await session.connect(args.single).timeout(const Duration(seconds: 40));
        _checkPaused(session);
        final connectedMs = clock.elapsedMilliseconds;
        final initialAck = session.snapshot.lastAckSequence!;
        phase = 'holding';
        for (var second = 0; second < 12; second++) {
          await Future<void>.delayed(const Duration(seconds: 1));
          _checkPaused(session);
        }
        final finalAck = session.snapshot.lastAckSequence!;
        if (finalAck <= initialAck ||
            (link.commands[BleOpcode.keepalive.value] ?? 0) < 3) {
          throw StateError('Keepalive acknowledgments did not advance');
        }
        final firmware = session.snapshot.deviceInfo!.firmwareVersion;
        phase = 'releasing';
        await session.release().timeout(const Duration(seconds: 8));
        disconnected = link.transport.currentState == BleLinkState.disconnected;
        if (!disconnected) throw StateError('Disconnect was not confirmed');
        final result = <String, Object?>{
          'round': round,
          'firmware': firmware,
          'connected_ms': connectedMs,
          'held_paused_seconds': 12,
          'keepalive_ack_advanced': true,
          'notifications_received': link.notifications,
          'read_counts': link.reads,
          'command_counts': {
            for (final entry in link.commands.entries)
              BleOpcode.values.firstWhere((op) => op.value == entry.key).name:
                  entry.value,
          },
          'disconnected': disconnected,
          'initial_diagnostics': link.firstDiagnostics,
          'latest_diagnostics': link.latestDiagnostics,
          'success': true,
        };
        rounds.add(result);
        print(jsonEncode(result));
      } catch (error) {
        print(
          jsonEncode({
            'round': round,
            'failed_phase': phase,
            'session_phase': session.snapshot.phase.name,
            'failure': error.toString(),
            'initial_diagnostics': link.firstDiagnostics,
            'latest_diagnostics': link.latestDiagnostics,
            'command_counts': {
              for (final entry in link.commands.entries)
                BleOpcode.values.firstWhere((op) => op.value == entry.key).name:
                    entry.value,
            },
          }),
        );
        rethrow;
      } finally {
        if (!disconnected) await session.disconnect();
        await session.dispose();
        await link.transport.dispose();
      }
      if (round < 3) await Future<void>.delayed(const Duration(seconds: 2));
    }
    print(jsonEncode({'success': true, 'rounds_passed': rounds.length}));
  } catch (error) {
    print(
      jsonEncode({
        'success': false,
        'rounds_passed': rounds.length,
        'failure_type': error.runtimeType.toString(),
      }),
    );
    exitCode = 1;
  }
}
