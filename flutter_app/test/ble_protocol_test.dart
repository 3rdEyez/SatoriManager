import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:satori_manager/core/ble_protocol.dart';

List<int> unhex(String value) => [
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
];
String hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('v1.2 shared-pairing info and unsupported transfer vectors', () {
    final vectors =
        jsonDecode(
              File(
                '../docs/protocol/satori_ble_v1_2_shared_pairing_vectors.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    for (final item in vectors['reads'] as List) {
      final vector = item as Map<String, dynamic>;
      final bytes = unhex(vector['hex'] as String);
      final info = BleProtocol.decodeDeviceInfo(bytes);
      expect(info.protocolMinor, vector['protocol_minor']);
      expect(info.capabilities, vector['capabilities']);
      expect(info.securityPolicy, vector['security_policy']);
      expect(info.supportsSharedPairing, isTrue);
      expect(
        hex(
          BleProtocol.encodeDeviceInfo(
            protocolMinor: 2,
            firmwareMajor: 0,
            firmwareMinor: 2,
            firmwarePatch: 2,
            hardwareProfile: 1,
            capabilities: 0x1df,
            securityPolicy: 2,
          ),
        ),
        vector['hex'],
      );
    }
    for (final item in vectors['rejection_cases'] as List) {
      final vector = item as Map<String, dynamic>;
      expect(
        BleProtocol.validateControlFrame(
          unhex(vector['hex'] as String),
          currentToken: 0x12345678,
          armed: false,
          subscribed: true,
          supportsSharedPairing: true,
        ).value,
        vector['expected_result'],
        reason: vector['name'] as String,
      );
    }
  });

  test('v1.1 management command, event and rejection vectors', () {
    final vectors =
        jsonDecode(
              File(
                '../docs/protocol/satori_ble_v1_1_management_vectors.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    for (final item in vectors['commands'] as List) {
      final vector = item as Map<String, dynamic>;
      final op = BleOpcode.values.firstWhere(
        (value) => value.value == vector['opcode'],
      );
      final payload = op == BleOpcode.setPairingCode
          ? BleProtocol.encodePairingCode(
              (vector['code'] as int).toString().padLeft(6, '0'),
            )
          : null;
      final frame = BleProtocol.encodeControlFrame(
        opcode: op,
        sequence: vector['sequence'] as int,
        token: vector['token'] as int,
        payload: payload,
      );
      expect(hex(frame), vector['hex'], reason: vector['name'] as String);
    }
    for (final item in vectors['events'] as List) {
      final vector = item as Map<String, dynamic>;
      final event = BleProtocol.decodeEvent(unhex(vector['hex'] as String));
      expect(event.opcode, greaterThanOrEqualTo(0x88));
      expect(
        hex(
          BleProtocol.encodeEvent(
            opcode: event.opcode,
            sequence: event.sequence,
            token: event.token,
            result: event.result,
            controlState: event.controlState,
            lastAppliedSequence: event.lastAppliedSequence,
            flags: event.flags,
            batteryPercent: event.batteryPercent,
          ),
        ),
        vector['hex'],
      );
    }
    for (final item in vectors['rejection_cases'] as List) {
      final vector = item as Map<String, dynamic>;
      expect(
        BleProtocol.validateControlFrame(
          unhex(vector['hex'] as String),
          currentToken: 0x12345678,
          armed: false,
          subscribed: true,
        ).value,
        vector['expected_result'],
        reason: vector['name'] as String,
      );
    }
  });

  test('all shared command vectors encode and decode exactly', () {
    const vectors = <List<Object>>[
      [BleOpcode.claim, 1, 0, '0101010000000000000000000000000000000000'],
      [
        BleOpcode.arm,
        2,
        0x12345678,
        '0107020000007856341200000000000000000000',
      ],
      [
        BleOpcode.setTarget,
        3,
        0x12345678,
        '01020300000078563412dc054006a406c8000000',
      ],
      [
        BleOpcode.keepalive,
        4,
        0x12345678,
        '0105040000007856341200000000000000000000',
      ],
      [
        BleOpcode.halt,
        5,
        0x12345678,
        '0103050000007856341200000000000000000000',
      ],
      [
        BleOpcode.getStatus,
        6,
        0x12345678,
        '0106060000007856341200000000000000000000',
      ],
      [
        BleOpcode.release,
        7,
        0x12345678,
        '0104070000007856341200000000000000000000',
      ],
      [
        BleOpcode.setTarget,
        65537,
        0x12345678,
        '01020100010078563412dc054006a406c8000000',
      ],
    ];
    for (final v in vectors) {
      final op = v[0] as BleOpcode,
          seq = v[1] as int,
          token = v[2] as int,
          expected = v[3] as String;
      final encoded = BleProtocol.encodeControlFrame(
        opcode: op,
        sequence: seq,
        token: token,
        payload: op == BleOpcode.setTarget
            ? BleProtocol.encodeSetTarget(
                ch1: 1500,
                ch2: 1600,
                ch3: 1700,
                transitionMs: 200,
              )
            : null,
      );
      expect(hex(encoded), expected);
      final decoded = BleProtocol.decodeControlFrame(unhex(expected));
      expect(decoded.version, 1);
      expect(decoded.opcode, op.value);
      expect(decoded.sequence, seq);
      expect(decoded.token, token);
    }
  });

  test(
    'all shared event vectors decode, including async and error replies',
    () {
      const vectors = <String>[
        '018101000000785634120001000000000cff0000',
        '018702000000785634120001020000000dff0000',
        '018203000000785634120001020000000dff0000',
        '01e000000000785634120002030000000fff0000',
        '018305000000785634120001050000000dff0000',
        '0184070000007856341200000700000005ff0000',
        '018203000000785634120b01000000000cff0000',
        '018702000000785634120c01000000000cff0000',
      ];
      for (final fixture in vectors) {
        final event = BleProtocol.decodeEvent(unhex(fixture));
        expect(
          hex(
            BleProtocol.encodeEvent(
              opcode: event.opcode,
              sequence: event.sequence,
              token: event.token,
              result: event.result,
              controlState: event.controlState,
              lastAppliedSequence: event.lastAppliedSequence,
              flags: event.flags,
              batteryPercent: event.batteryPercent,
            ),
          ),
          fixture,
        );
      }
      expect(BleProtocol.decodeEvent(unhex(vectors[0])).token, 0x12345678);
      expect(BleProtocol.decodeEvent(unhex(vectors[3])).controlState, 2);
      expect(
        BleProtocol.decodeEvent(unhex(vectors[6])).result,
        BleResult.notArmed,
      );
      expect(
        BleProtocol.decodeEvent(unhex(vectors[7])).result,
        BleResult.notConfigured,
      );
    },
  );

  test('all shared read vectors decode and re-encode byte-for-byte', () {
    const info = '0100000100015f0000001414d007701701030000';
    const identity = '00112233445566778899aabbccddeeff';
    const cold = '010000000000000000000000000000000000ff00';
    const armed = '01017856341202000000b405fa0572060700ff00';
    const moving = '01027856341203000000c805180690060707ff00';
    final d = BleProtocol.decodeDeviceInfo(unhex(info));
    expect(d.firmwareVersion, '0.1.0');
    expect(d.capabilities, 0x5f);
    expect(d.maxTransitionMs, 2000);
    expect(d.leaseTimeoutMs, 6000);
    expect(hex(BleProtocol.encodeDeviceInfo(firmwareMinor: 1)), info);
    expect(hex(BleProtocol.decodeIdentity(unhex(identity))), identity);
    for (final fixture in [cold, armed, moving]) {
      final s = BleProtocol.decodeStateSnapshot(unhex(fixture));
      expect(
        hex(
          BleProtocol.encodeStateSnapshot(
            controlState: s.controlState,
            token: s.token,
            lastAppliedSequence: s.lastAppliedSequence,
            channels: s.channels,
            validChannelMask: s.validChannelMask,
            interpolatingChannelMask: s.interpolatingChannelMask,
            batteryPercent: s.batteryPercent,
          ),
        ),
        fixture,
      );
    }
    expect(BleProtocol.decodeStateSnapshot(unhex(cold)).validChannelMask, 0);
    expect(
      BleProtocol.decodeStateSnapshot(unhex(moving)).interpolatingChannelMask,
      7,
    );
  });

  test('all shared rejection fixtures map to their protocol result', () {
    const cases = <List<Object>>[
      ['01020300000078563412dc054006a406c80000', BleResult.badLength],
      ['01020300000078563412dc054006a406c800000000', BleResult.badLength],
      ['02020300000078563412dc054006a406c8000000', BleResult.badVersion],
      ['017f030000007856341200000000000000000000', BleResult.badOpcode],
      ['01020300000078563412f3014006a406c8000000', BleResult.badPayload],
      ['01020300000078563412dc054006c509c8000000', BleResult.badPayload],
      ['01020300000078563412dc054006a406d1070000', BleResult.badPayload],
      ['01020300000078563412dc054006a406c8000100', BleResult.badPayload],
      ['0103050000007856341201000000000000000000', BleResult.badPayload],
      ['01020000000078563412dc054006a406c8000000', BleResult.oldSequence],
      ['01020300000099999999dc054006a406c8000000', BleResult.badSession],
      ['01020300000078563412dc054006a406c8000000', BleResult.notArmed],
      [
        '0101010000000000000000000000000000000000',
        BleResult.subscriptionRequired,
      ],
    ];
    for (final c in cases) {
      final bytes = unhex(c[0] as String);
      final expected = c[1] as BleResult;
      expect(
        BleProtocol.validateControlFrame(
          bytes,
          currentToken: 0x12345678,
          armed: false,
          subscribed: false,
        ),
        expected,
        reason: c[0] as String,
      );
    }
    // Secure ATT failures (unauthenticated controls) happen below this codec.
  });

  test(
    'rejects malformed lengths, field values, reserved bits and unknown enum values',
    () {
      expect(() => BleProtocol.decodeControlFrame([1]), throwsFormatException);
      expect(() => BleProtocol.decodeIdentity([1]), throwsFormatException);
      expect(
        () => BleProtocol.decodeEvent(List.filled(20, 0)),
        throwsFormatException,
      );
      expect(
        () => BleProtocol.decodeDeviceInfo(List.filled(20, 0)),
        throwsFormatException,
      );
      expect(
        () => BleProtocol.decodeStateSnapshot(List.filled(20, 0)),
        throwsFormatException,
      );
      expect(
        () => BleProtocol.encodeSetTarget(
          ch1: 499,
          ch2: 1500,
          ch3: 1700,
          transitionMs: 200,
        ),
        throwsFormatException,
      );
      expect(
        () => BleProtocol.encodeSetTarget(
          ch1: 1500,
          ch2: 1600,
          ch3: 1700,
          transitionMs: 2001,
        ),
        throwsFormatException,
      );
      final badEvent = unhex('018101000000785634120001000000000cff0000')
        ..[18] = 1;
      expect(() => BleProtocol.decodeEvent(badEvent), throwsFormatException);
      final badSnapshot = unhex('01017856341202000000b405fa0572060700ff00')
        ..[19] = 1;
      expect(
        () => BleProtocol.decodeStateSnapshot(badSnapshot),
        throwsFormatException,
      );
    },
  );
}
