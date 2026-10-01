// CLI output is intentionally direct and contains no session tokens/passkeys.
// ignore_for_file: avoid_print

import 'dart:async';

import 'package:satori_manager/core/device_session.dart';
import 'package:satori_manager/infrastructure/bluez_ble_link.dart';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options.showHelp) return;
  final link = BluezBleLink();
  final session = DeviceSession(link);
  try {
    if (options.deviceId == null) {
      print('Scanning for SatoriEye BLE peripherals for 8 seconds…');
      await for (final device in link.scan()) {
        print(
          '${device.name.isEmpty ? '(unnamed)' : device.name}  RSSI ${device.rssi}  ${device.id}',
        );
      }
      print(
        'No control connection opened. Re-run with --device <address> to connect.',
      );
      return;
    }

    await session.connect(options.deviceId!);
    final info = session.snapshot.deviceInfo!;
    final state = session.snapshot.state!;
    print(
      'Connected and claimed; protocol ${info.protocolMajor}.${info.protocolMinor}, '
      'firmware ${info.firmwareVersion}.',
    );
    print(
      'State code: ${state.controlState}; output known: ${state.targetKnown}; '
      'battery: ${state.batteryPercent?.toString() ?? 'unknown'}.',
    );

    if (options.arm) {
      await session.arm();
      print(
        'ARM accepted; known logical output: ${session.snapshot.state?.channels}.',
      );
    }
    if (options.target case final target?) {
      if (!options.arm) {
        throw FormatException('--target requires explicit --arm');
      }
      await session.setTarget(
        ch1: target[0],
        ch2: target[1],
        ch3: target[2],
        transitionMs: 0,
      );
      print('SET_TARGET accepted for the three requested logical channels.');
      await session.halt();
      print('HALT acknowledged.');
    }
  } finally {
    await session.disconnect();
    await session.dispose();
    await link.dispose();
  }
}

class _Options {
  const _Options({
    this.deviceId,
    this.arm = false,
    this.target,
    this.showHelp = false,
  });
  final String? deviceId;
  final bool arm;
  final List<int>? target;
  final bool showHelp;

  static _Options parse(List<String> args) {
    String? deviceId;
    var arm = false;
    List<int>? target;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--device' && i + 1 < args.length) {
        deviceId = args[++i];
      } else if (arg == '--arm') {
        arm = true;
      } else if (arg.startsWith('--target=')) {
        final values = arg.substring('--target='.length).split(',');
        if (values.length != 3) {
          throw const FormatException('Target must be CH1,CH2,CH3');
        }
        target = values
            .map((value) {
              final parsed = int.tryParse(value);
              if (parsed == null || parsed < 500 || parsed > 2500) {
                throw const FormatException('Each target must be 500–2500');
              }
              return parsed;
            })
            .toList(growable: false);
      } else if (arg == '--help' || arg == '-h') {
        print(
          'Usage: dart run tool/ble_probe.dart [--device <address>] [--arm] [--target=CH1,CH2,CH3]',
        );
        print(
          'Without --device the tool scans only. Connection never arms unless --arm is explicit.',
        );
        return const _Options(showHelp: true);
      } else {
        throw FormatException('Unknown or incomplete option: $arg');
      }
    }
    if (target != null && !arm) {
      throw const FormatException('--target requires --arm');
    }
    return _Options(deviceId: deviceId, arm: arm, target: target);
  }
}
