import 'package:flutter_test/flutter_test.dart';
import 'package:satori_manager/core/ble_protocol.dart';
import 'package:satori_manager/core/device_session.dart';
import 'package:satori_manager/infrastructure/fake_ble_link.dart';

void main() {
  test(
    'three phones share one passkey and bonds survive code rotation',
    () async {
      final device = FakeBleSharedDevice();
      for (final phone in ['phone-a', 'phone-b', 'phone-c']) {
        expect(device.pairPhone(phone, '123456'), isTrue);
      }
      expect(device.bondedPhones, {'phone-a', 'phone-b', 'phone-c'});

      final link = FakeBleLink(sharedDevice: device, phoneId: 'phone-a');
      final session = DeviceSession(link);
      await session.connect('peripheral');
      await session.setPairingCode('654321');
      await session.disconnect();
      await session.dispose();
      await link.dispose();
      expect(device.pairingCode, 654321);
      expect(device.bondedPhones, {'phone-a', 'phone-b', 'phone-c'});
      expect(device.pairPhone('phone-d', '123456'), isFalse);
      expect(device.pairPhone('phone-d', '654321'), isTrue);
      expect(
        device.bondedPhones,
        containsAll(['phone-a', 'phone-b', 'phone-c', 'phone-d']),
      );
    },
  );

  test('shared bond table accepts eight phones and refuses a ninth', () {
    final device = FakeBleSharedDevice();
    for (var index = 0; index < 8; index++) {
      final phone = 'phone-$index';
      expect(device.pairPhone(phone, '123456'), isTrue);
    }
    expect(device.bondedPhones, hasLength(8));
    expect(device.pairPhone('phone-overflow', '123456'), isFalse);
  });

  test(
    'one bonded phone controls at a time, then the next phone can connect',
    () async {
      final device = FakeBleSharedDevice();
      expect(device.pairPhone('phone-a', '123456'), isTrue);
      expect(device.pairPhone('phone-b', '123456'), isTrue);
      final firstLink = FakeBleLink(sharedDevice: device, phoneId: 'phone-a');
      final secondLink = FakeBleLink(sharedDevice: device, phoneId: 'phone-b');
      final first = DeviceSession(firstLink);
      final second = DeviceSession(secondLink);

      await first.connect('peripheral');
      expect(first.snapshot.isConnected, isTrue);
      expect(device.pairPhone('phone-c', '123456'), isFalse);
      expect(device.setPairingCode('phone-b', 654321), isFalse);
      await expectLater(second.connect('peripheral'), throwsStateError);
      expect(second.snapshot.phase, DeviceSessionPhase.error);
      expect(device.activePhone, 'phone-a');

      await first.disconnect();
      expect(device.pairPhone('phone-c', '123456'), isTrue);
      await second.connect('peripheral');
      expect(second.snapshot.phase, DeviceSessionPhase.readyPaused);
      expect(second.snapshot.isArmed, isFalse);
      expect(device.activePhone, 'phone-b');

      await second.disconnect();
      await first.dispose();
      await second.dispose();
      await firstLink.dispose();
      await secondLink.dispose();
    },
  );

  test(
    'shared pairing reports minor 2 policy 2 and rejects transfer commands',
    () async {
      final link = FakeBleLink();
      final session = DeviceSession(link);
      await session.connect('peripheral');
      expect(session.snapshot.deviceInfo?.protocolMinor, 2);
      expect(session.snapshot.deviceInfo?.securityPolicy, 2);
      expect(session.snapshot.deviceInfo?.supportsSharedPairing, isTrue);
      await expectLater(
        session.openTransfer(),
        throwsA(
          isA<BleCommandRejected>().having(
            (error) => error.result,
            'result',
            BleResult.badOpcode,
          ),
        ),
      );
      await expectLater(
        session.cancelTransfer(),
        throwsA(
          isA<BleCommandRejected>().having(
            (error) => error.result,
            'result',
            BleResult.badOpcode,
          ),
        ),
      );
      expect(session.snapshot.isConnected, isTrue);
      await session.disconnect();
      await session.dispose();
      await link.dispose();
    },
  );

  test(
    'failed connection releases exclusive slot for another bonded phone',
    () async {
      final device = FakeBleSharedDevice();
      device.pairPhone('phone-a', '123456');
      device.pairPhone('phone-b', '123456');
      final firstLink = FakeBleLink(sharedDevice: device, phoneId: 'phone-a');
      final secondLink = FakeBleLink(sharedDevice: device, phoneId: 'phone-b');
      final first = DeviceSession(firstLink);
      final second = DeviceSession(secondLink);
      await expectLater(
        first.connect(
          'peripheral',
          expectedIdentity: 'ffffffffffffffffffffffffffffffff',
        ),
        throwsStateError,
      );
      expect(device.activePhone, isNull);
      await second.connect('peripheral');
      expect(second.snapshot.phase, DeviceSessionPhase.readyPaused);
      expect(device.activePhone, 'phone-b');
      await second.disconnect();
      await first.dispose();
      await second.dispose();
      await firstLink.dispose();
      await secondLink.dispose();
    },
  );
}
