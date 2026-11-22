import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:satori_manager/core/ble_protocol.dart';
import 'package:satori_manager/infrastructure/gatt_discovery.dart';

const lan = '4d89f6a0-73b9-4f14-9d3e-63b2145a0008';

void main() {
  test(
    'native evidence arriving after reset cannot belong to the next connection',
    () async {
      final discovery = GattDiscovery();
      addTearDown(discovery.dispose);
      final evidence = Completer<Map<String, Object?>>();
      final pending = discovery.discover(
        () async => {BleProtocol.serviceUuid: []},
        nativeEvidence: () => evidence.future,
      );
      await Future<void>.delayed(Duration.zero);
      discovery.reset();
      await discovery.discover(
        () async => {
          BleProtocol.serviceUuid: [lan],
        },
      );
      evidence.complete({'phase': 'completed', 'operation': 99});
      await pending;
      expect(discovery.diagnostics['0008'], true);
      expect(discovery.diagnostics['native'], isEmpty);
    },
  );
  test(
    'explicit discovery distinguishes present and missing optional UUIDs',
    () async {
      final discovery = GattDiscovery();
      addTearDown(discovery.dispose);
      await discovery.discover(
        () async => {
          BleProtocol.serviceUuid.toUpperCase(): [lan.toUpperCase()],
        },
      );
      expect(discovery.diagnostics['phase'], 'completed');
      expect(discovery.diagnostics['0008'], true);
      expect(discovery.diagnostics['0007'], false);
      expect(discovery.diagnostics['0006'], false);
      expect(discovery.contains(lan), true);
    },
  );

  test(
    'native failure exposes safe category and never reports absence',
    () async {
      final discovery = GattDiscovery();
      addTearDown(discovery.dispose);
      await discovery.discover(
        () async => throw StateError('synthetic-private-native-text'),
      );
      expect(discovery.diagnostics['failure'], 'nativeDiscoveryFailed');
      expect(discovery.diagnostics['0008'], null);
      expect(
        discovery.diagnostics.toString(),
        isNot(contains('synthetic-private')),
      );
    },
  );

  test(
    'missing primary service preserves returned UUIDs with unknown capability',
    () async {
      final discovery = GattDiscovery();
      addTearDown(discovery.dispose);
      await discovery.discover(
        () async => {'00001800-0000-1000-8000-00805f9b34fb': []},
      );
      expect(discovery.diagnostics['phase'], 'missingService');
      expect(discovery.diagnostics['0008'], null);
      expect(discovery.diagnostics['services'], isNotEmpty);
    },
  );

  test(
    'timeout cannot become missing or later overwrite failed diagnostic',
    () async {
      final discovery = GattDiscovery();
      addTearDown(discovery.dispose);
      final query = Completer<Map<String, List<String>>>();
      await discovery.discover(
        () => query.future,
        timeout: const Duration(milliseconds: 1),
      );
      expect(discovery.diagnostics['failure'], 'timeout');
      expect(discovery.contains(lan), null);
      query.complete({
        BleProtocol.serviceUuid: [lan],
      });
      await Future<void>.delayed(Duration.zero);
      expect(discovery.diagnostics['phase'], 'failed');
    },
  );

  test(
    'disconnect reset fences late discovery and clears previous device UUIDs',
    () async {
      final discovery = GattDiscovery();
      addTearDown(discovery.dispose);
      final query = Completer<Map<String, List<String>>>();
      final pending = discovery.discover(() => query.future);
      expect(discovery.diagnostics['phase'], 'discovering');
      discovery.reset();
      await discovery.discover(() async => {BleProtocol.serviceUuid: []});
      query.complete({
        BleProtocol.serviceUuid: [lan],
      });
      await pending;
      expect(discovery.diagnostics['0008'], false);
      discovery.reset();
      expect(discovery.diagnostics['services'], isEmpty);
      expect(discovery.diagnostics['0008'], null);
    },
  );
}
