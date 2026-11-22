import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:satori_manager/core/ble_protocol.dart';
import 'package:satori_manager/core/device_session.dart';
import 'package:satori_manager/core/lan_window.dart';
import 'package:satori_manager/infrastructure/reactive_ble_link.dart';

class TestCharacteristic extends Fake implements Characteristic {
  TestCharacteristic(this.id);
  @override
  final Uuid id;
}

class TestService extends Fake implements Service {
  @override
  Uuid get id => Uuid.parse(BleProtocol.serviceUuid);
  @override
  final List<Characteristic> characteristics;
  TestService(this.characteristics);
}

class TestBle extends Fake implements FlutterReactiveBle {
  final connection = StreamController<ConnectionStateUpdate>();
  final calls = <String>[];
  bool failDiscovery = false;
  bool denyRead = false;
  bool hasLan = true;
  @override
  Stream<ConnectionStateUpdate> connectToDevice({
    required String id,
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
    Duration? connectionTimeout,
  }) {
    scheduleMicrotask(
      () => connection.add(
        ConnectionStateUpdate(
          deviceId: id,
          connectionState: DeviceConnectionState.connected,
          failure: null,
        ),
      ),
    );
    return connection.stream;
  }

  @override
  Future<void> discoverAllServices(String deviceId) async {
    calls.add('discover');
    if (failDiscovery) throw StateError('synthetic-private');
  }

  @override
  Future<List<Service>> getDiscoveredServices(String deviceId) async {
    calls.add('list');
    return [
      TestService(
        hasLan ? [TestCharacteristic(Uuid.parse(LanWindowStatus.lanUuid))] : [],
      ),
    ];
  }

  @override
  Future<List<int>> readCharacteristic(
    QualifiedCharacteristic characteristic,
  ) async {
    calls.add('read');
    if (denyRead) throw StateError('GATT_READ_NOT_PERMIT synthetic-private');
    return [1];
  }
}

void main() {
  test(
    'read rejection reports UUID without native private error text',
    () async {
      final ble = TestBle()..denyRead = true;
      final link = ReactiveBleLink(ble: ble);
      addTearDown(() async {
        await link.dispose();
        await ble.connection.close();
      });
      await link.connect('synthetic');
      await expectLater(
        link.read(BleProtocol.stateSnapshotUuid),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'public diagnosis',
            allOf(
              contains(BleProtocol.stateSnapshotUuid),
              contains('GATT_READ_NOT_PERMIT'),
              isNot(contains('synthetic-private')),
            ),
          ),
        ),
      );
    },
  );
  test(
    'native Service Changed disconnect marker is retained for the control policy',
    () async {
      final ble = TestBle();
      final link = ReactiveBleLink(ble: ble);
      addTearDown(() async {
        await link.dispose();
        await ble.connection.close();
      });
      await link.connect('synthetic');
      ble.connection.addError(StateError('satoriServiceChanged'));
      await Future<void>.delayed(Duration.zero);
      expect(link.gattDatabaseChanged, true);
      expect(link.currentState, BleLinkState.disconnected);
      expect(link.gattDiagnostics['0008'], null);
    },
  );
  test(
    'transport explicitly discovers before optional read and exports UUIDs',
    () async {
      final ble = TestBle();
      final link = ReactiveBleLink(ble: ble);
      addTearDown(() async {
        await link.dispose();
        await ble.connection.close();
      });
      await link.connect('synthetic');
      expect(ble.calls, ['discover', 'list']);
      expect(link.gattDiagnostics['0008'], true);
      expect(await link.read(LanWindowStatus.lanUuid), [1]);
      expect(ble.calls, ['discover', 'list', 'read']);
      await link.disconnect();
      expect(link.gattDiagnostics['0008'], null);
    },
  );
  test(
    'discovery failure prevents absence classification and unsafe read',
    () async {
      final ble = TestBle()..failDiscovery = true;
      final link = ReactiveBleLink(ble: ble);
      addTearDown(() async {
        await link.dispose();
        await ble.connection.close();
      });
      await link.connect('synthetic');
      expect(link.gattDiagnostics['phase'], 'failed');
      await expectLater(link.read(LanWindowStatus.lanUuid), throwsStateError);
      await expectLater(link.read(BleProtocol.serviceUuid), throwsStateError);
      expect(() => link.write(BleProtocol.serviceUuid, [1]), throwsStateError);
      expect(() => link.subscribe(BleProtocol.serviceUuid), throwsStateError);
      expect(ble.calls, ['discover']);
    },
  );
  test(
    'successful primary discovery with missing optional feature is explicit',
    () async {
      final ble = TestBle()..hasLan = false;
      final link = ReactiveBleLink(ble: ble);
      addTearDown(() async {
        await link.dispose();
        await ble.connection.close();
      });
      await link.connect('synthetic');
      expect(link.gattDiagnostics['0008'], false);
      await expectLater(
        link.read(LanWindowStatus.lanUuid),
        throwsA(isA<BleCharacteristicAbsent>()),
      );
      expect(ble.calls, ['discover', 'list']);
    },
  );
  test(
    'transport attaches native evidence after the real discovery query',
    () async {
      final ble = TestBle();
      final link = ReactiveBleLink(
        ble: ble,
        nativeDiscoveryEvidence: (id) async {
          expect(ble.calls, ['discover', 'list']);
          return {
            'phase': 'completed',
            'accepted': true,
            'callbackReceived': true,
            'startedAtMs': 100,
            'completedAtMs': 150,
            'status': 0,
            'address': 'never-export-this',
          };
        },
      );
      addTearDown(() async {
        await link.dispose();
        await ble.connection.close();
      });
      await link.connect('synthetic');
      final native = link.gattDiagnostics['native'] as Map;
      expect(native['callbackReceived'], true);
      expect(native['completedAtMs'], 150);
      expect(native.containsKey('address'), false);
      await link.disconnect();
      expect(link.gattDiagnostics['native'], isEmpty);
    },
  );
}
