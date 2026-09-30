import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:satori_manager/core/ble_compatibility.dart';
import 'package:satori_manager/core/ble_protocol.dart';
import 'package:satori_manager/core/device_session.dart';
import 'package:satori_manager/infrastructure/fake_ble_link.dart';

class VersionedLink implements BleLink {
  VersionedLink(this.inner, this.info);
  final FakeBleLink inner;
  final List<int> info;
  bool protectedRead = false;

  @override
  Stream<BleLinkState> get connectionState => inner.connectionState;
  @override
  Future<void> connect(String id) => inner.connect(id);
  @override
  Future<void> disconnect() => inner.disconnect();
  @override
  Future<List<int>> read(String uuid) {
    if (uuid == BleProtocol.deviceInfoUuid) return Future.value(info);
    if (uuid == BleProtocol.stateSnapshotUuid) protectedRead = true;
    return inner.read(uuid);
  }

  @override
  Future<void> write(String uuid, List<int> value) => inner.write(uuid, value);
  @override
  Stream<List<int>> subscribe(String uuid) => inner.subscribe(uuid);
}

void main() {
  test('declared app version stays in sync with pubspec', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('version: ${BleCompatibility.appVersion}+'),
    );
  });
  test(
    'patch differences remain compatible; major, minor and protocol do not',
    () {
      BleDeviceInfo decode({
        int major = 0,
        int minor = 2,
        int patch = 99,
        int protocol = 2,
      }) => BleProtocol.decodeDeviceInfo(
        BleProtocol.encodeDeviceInfo(
          protocolMinor: protocol,
          firmwareMajor: major,
          firmwareMinor: minor,
          firmwarePatch: patch,
        ),
      );
      expect(BleCompatibility.incompatibility(decode()), isNull);
      expect(BleCompatibility.incompatibility(decode(major: 1)), isNotNull);
      expect(BleCompatibility.incompatibility(decode(minor: 3)), isNotNull);
      expect(BleCompatibility.incompatibility(decode(protocol: 1)), isNotNull);
    },
  );

  test(
    'incompatible version is rejected before protected pairing read',
    () async {
      final inner = FakeBleLink();
      final link = VersionedLink(
        inner,
        BleProtocol.encodeDeviceInfo(protocolMinor: 2, firmwareMinor: 3),
      );
      final session = DeviceSession(link);
      await expectLater(
        session.connect('synthetic'),
        throwsA(isA<BleVersionMismatch>()),
      );
      expect(link.protectedRead, isFalse);
      expect(inner.writes, isEmpty);
      await session.dispose();
      await inner.dispose();
    },
  );
}
