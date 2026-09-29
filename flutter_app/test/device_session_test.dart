import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:satori_manager/core/ble_protocol.dart';
import 'package:satori_manager/core/device_session.dart';
import 'package:satori_manager/infrastructure/fake_ble_link.dart';

List<int> frame(BleOpcode op, int seq, int token, {List<int>? payload}) =>
    BleProtocol.encodeControlFrame(
      opcode: op,
      sequence: seq,
      token: token,
      payload: payload,
    );
String byteHex(List<int> bytes) =>
    bytes.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Future<List<int>> exchange(FakeBleLink link, List<int> request) async {
  final f = BleProtocol.decodeControlFrame(request);
  final completer = Completer<List<int>>();
  late StreamSubscription<List<int>> sub;
  sub = link.subscribe(BleProtocol.eventTxUuid).listen((bytes) {
    try {
      final e = BleProtocol.decodeEvent(bytes);
      if (e.sequence == f.sequence &&
          e.opcode == (f.opcode | 0x80) &&
          !completer.isCompleted) {
        completer.complete(List<int>.from(bytes));
      }
    } catch (_) {}
  });
  await link.write(BleProtocol.controlRxUuid, request);
  try {
    return await completer.future.timeout(const Duration(milliseconds: 100));
  } finally {
    await sub.cancel();
  }
}

class AckBeforeWriteCompletes implements BleLink {
  AckBeforeWriteCompletes(this.inner);
  final FakeBleLink inner;
  final List<int> ackBeforeWriteOpcodes = [];
  @override
  Stream<BleLinkState> get connectionState => inner.connectionState;
  @override
  Future<void> connect(String id) => inner.connect(id);
  @override
  Future<void> disconnect() => inner.disconnect();
  @override
  Future<List<int>> read(String uuid) => inner.read(uuid);
  @override
  Stream<List<int>> subscribe(String uuid) => inner.subscribe(uuid);
  @override
  Future<void> write(String uuid, List<int> value) async {
    final frame = BleProtocol.decodeControlFrame(value);
    var ackSeen = false;
    final observer = inner.subscribe(BleProtocol.eventTxUuid).listen((event) {
      try {
        final decoded = BleProtocol.decodeEvent(event);
        if (decoded.sequence == frame.sequence &&
            decoded.opcode == (frame.opcode | 0x80)) {
          ackSeen = true;
        }
      } catch (_) {}
    });
    await inner.write(uuid, value);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (ackSeen) ackBeforeWriteOpcodes.add(frame.opcode);
    await observer.cancel();
  }
}

class PairingWriteFailureLink implements BleLink {
  PairingWriteFailureLink(this.inner);
  final FakeBleLink inner;
  @override
  Stream<BleLinkState> get connectionState => inner.connectionState;
  @override
  Future<void> connect(String id) => inner.connect(id);
  @override
  Future<void> disconnect() => inner.disconnect();
  @override
  Future<List<int>> read(String uuid) => inner.read(uuid);
  @override
  Stream<List<int>> subscribe(String uuid) => inner.subscribe(uuid);
  @override
  Future<void> write(String uuid, List<int> value) {
    if (BleProtocol.decodeControlFrame(value).opcode ==
        BleOpcode.setPairingCode.value) {
      throw StateError('raw pairing payload includes 654321');
    }
    return inner.write(uuid, value);
  }
}

void main() {
  test(
    'connect claims only after event subscription, then arm and target',
    () async {
      final link = FakeBleLink();
      final session = DeviceSession(
        link,
        commandTimeout: const Duration(milliseconds: 30),
      );
      await session.connect('synthetic');
      expect(session.snapshot.phase, DeviceSessionPhase.readyPaused);
      expect(session.snapshot.identity, '000102030405060708090a0b0c0d0e0f');
      expect(session.snapshot.deviceInfo?.protocolMajor, 1);
      expect(link.writes.first[1], 1);
      expect(session.snapshot.targetKnown, isFalse);
      expect(session.snapshot.state?.validChannelMask, 0);
      expect(link.acceptedTargetSubmissions, 0);
      await session.arm();
      expect(session.snapshot.isArmed, isTrue);
      await session.setTarget(
        ch1: 1500,
        ch2: 1600,
        ch3: 1700,
        latestOnly: false,
      );
      expect(link.writes.last[1], 2);
      await session.halt();
      expect(session.snapshot.phase, DeviceSessionPhase.readyPaused);
      await session.disconnect();
      await session.dispose();
      await link.dispose();
    },
  );
  test(
    'owner code changes use cached identical retries without exposing code',
    () async {
      final link = FakeBleLink();
      final session = DeviceSession(
        link,
        commandTimeout: const Duration(milliseconds: 30),
        maxRetries: 2,
      );
      await session.connect('synthetic');
      link.dropNextReplies = 1;
      await expectLater(
        session.setPairingCode('123456'),
        throwsFormatException,
      );
      await expectLater(
        session.setPairingCode('12x456'),
        throwsFormatException,
      );
      expect(
        link.writes.where(
          (frame) => frame[1] == BleOpcode.setPairingCode.value,
        ),
        isEmpty,
      );
      await session.setPairingCode('000042');
      expect(link.pairingCode, 42);
      final writes = link.writes
          .where((frame) => frame[1] == BleOpcode.setPairingCode.value)
          .toList();
      expect(writes, hasLength(2));
      expect(writes[0], writes[1]);
      expect(link.pairingCodeWrites, 1);
      expect(session.snapshot.toString(), isNot(contains('000042')));
      await session.disconnect();
      await session.dispose();
      await link.dispose();
    },
  );
  test(
    'management authorization callback runs at queue send boundary',
    () async {
      final link = FakeBleLink();
      final session = DeviceSession(link);
      await session.connect('synthetic');
      final writesBefore = link.writes.length;
      await expectLater(
        session.setPairingCode(
          '654321',
          beforeSend: () => throw StateError('UI client retired'),
        ),
        throwsStateError,
      );
      expect(link.writes, hasLength(writesBefore));
      expect(link.pairingCode, 123456);
      await session.disconnect();
      await session.dispose();
      await link.dispose();
    },
  );
  test(
    'queued ARM checks its action generation immediately before writing',
    () async {
      final link = FakeBleLink();
      final session = DeviceSession(link);
      await session.connect('synthetic');
      await expectLater(
        session.arm(
          beforeSend: () => throw StateError('automatic start paused'),
        ),
        throwsStateError,
      );
      expect(
        link.writes.where((frame) => frame[1] == BleOpcode.arm.value),
        isEmpty,
      );
      expect(session.snapshot.phase, DeviceSessionPhase.readyPaused);
      await session.disconnect();
      await session.dispose();
      await link.dispose();
    },
  );

  test(
    'management write exceptions are sanitized before reaching callers',
    () async {
      final inner = FakeBleLink();
      final session = DeviceSession(
        PairingWriteFailureLink(inner),
        commandTimeout: const Duration(milliseconds: 40),
        maxRetries: 0,
      );
      await session.connect('synthetic');
      await expectLater(
        session.setPairingCode('654321'),
        throwsA(
          predicate<Object>((error) => !error.toString().contains('654321')),
        ),
      );
      expect(session.snapshot.lastError, isNot(contains('654321')));
      expect(session.snapshot.phase, DeviceSessionPhase.disconnected);
      await session.dispose();
      await inner.dispose();
    },
  );

  test(
    'owner operations require capability and device owner authorization',
    () async {
      final unsupported = FakeBleLink(ownerManagementSupported: false);
      final oldSession = DeviceSession(unsupported);
      await oldSession.connect('synthetic');
      await expectLater(
        oldSession.setPairingCode('654321'),
        throwsA(isA<StateError>()),
      );
      expect(unsupported.writes.length, 1); // CLAIM only.
      await oldSession.disconnect();
      await oldSession.dispose();
      await unsupported.dispose();

      final stranger = FakeBleLink(ownerAuthorized: false);
      final strangerSession = DeviceSession(stranger);
      await strangerSession.connect('synthetic');
      await expectLater(
        strangerSession.setPairingCode('654321'),
        throwsA(isA<BleCommandRejected>()),
      );
      expect(stranger.pairingCode, 123456);
      expect(stranger.pairingCodeWrites, 0);
      await strangerSession.dispose();
      await stranger.dispose();
    },
  );

  test('NVS failure preserves pairing code and fails closed', () async {
    final link = FakeBleLink(nvsWriteFailures: 1);
    final session = DeviceSession(link);
    await session.connect('synthetic');
    await expectLater(
      session.setPairingCode('654321'),
      throwsA(
        isA<BleCommandRejected>().having(
          (error) => error.result,
          'result',
          BleResult.internalError,
        ),
      ),
    );
    expect(link.pairingCode, 123456);
    expect(link.pairingCodeWrites, 0);
    expect(session.snapshot.isConnected, isFalse);
    await session.dispose();
    await link.dispose();
  });

  test(
    'default code blocks transfer; transfer window times out without owner replacement',
    () async {
      final link = FakeBleLink(
        transferWindowTimeout: const Duration(milliseconds: 40),
        sharedPairingSupported: false,
      );
      final session = DeviceSession(link);
      await session.connect('synthetic');
      await expectLater(
        session.openTransfer(),
        throwsA(
          isA<BleCommandRejected>().having(
            (error) => error.result,
            'result',
            BleResult.notConfigured,
          ),
        ),
      );
      expect(session.snapshot.isConnected, isTrue);
      await session.setPairingCode('654321');
      await session.openTransfer();
      expect(link.transferWindowOpen, isTrue);
      expect(session.snapshot.phase, DeviceSessionPhase.disconnected);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(link.transferWindowOpen, isFalse);
      expect(link.pairingCode, 654321);
      expect(link.ownerIdentityUnchanged, isTrue);
      await session.dispose();
      await link.dispose();
    },
  );

  test('OPEN ACK before GATT write completion is treated as success', () async {
    final inner = FakeBleLink(sharedPairingSupported: false);
    final link = AckBeforeWriteCompletes(inner);
    final session = DeviceSession(
      link,
      commandTimeout: const Duration(milliseconds: 100),
    );
    await session.connect('synthetic');
    await session.setPairingCode('654321');
    await session.openTransfer();
    expect(link.ackBeforeWriteOpcodes, contains(BleOpcode.openTransfer.value));
    expect(session.snapshot.phase, DeviceSessionPhase.disconnected);
    expect(inner.transferWindowOpen, isTrue);
    await session.dispose();
    await inner.dispose();
  });

  test('OPEN without ACK times out and disconnects safely', () async {
    final link = FakeBleLink(sharedPairingSupported: false);
    final session = DeviceSession(
      link,
      commandTimeout: const Duration(milliseconds: 20),
      maxRetries: 1,
    );
    await session.connect('synthetic');
    await session.setPairingCode('654321');
    link.dropNextReplies = 2;
    await expectLater(session.openTransfer(), throwsA(isA<TimeoutException>()));
    expect(session.snapshot.phase, DeviceSessionPhase.disconnected);
    expect(link.currentState, BleLinkState.disconnected);
    await session.dispose();
    await link.dispose();
  });

  test(
    'device reboot closes transfer window but retains persisted code',
    () async {
      final link = FakeBleLink(sharedPairingSupported: false);
      final session = DeviceSession(link);
      await session.connect('synthetic');
      await session.setPairingCode('654321');
      await session.openTransfer();
      expect(link.transferWindowOpen, isTrue);
      await link.reboot();
      expect(link.transferWindowOpen, isFalse);
      expect(link.pairingCode, 654321);
      expect(link.ownerIdentityUnchanged, isTrue);
      await session.dispose();
      await link.dispose();
    },
  );

  test(
    'cancel transfer is idempotent when no transfer window is open',
    () async {
      final link = FakeBleLink(sharedPairingSupported: false);
      final session = DeviceSession(link);
      await session.connect('synthetic');
      await session.setPairingCode('654321');
      await session.cancelTransfer();
      await session.cancelTransfer();
      expect(link.transferWindowOpen, isFalse);
      await session.disconnect();
      await session.dispose();
      await link.dispose();
    },
  );
  test(
    'transfer replay does not extend window; duplicate OPEN is busy',
    () async {
      final link = FakeBleLink(
        transferWindowTimeout: const Duration(milliseconds: 150),
        sharedPairingSupported: false,
      );
      await link.connect('synthetic');
      final claim = BleProtocol.decodeEvent(
        await exchange(link, frame(BleOpcode.claim, 1, 0)),
      );
      final token = claim.token;
      await exchange(
        link,
        frame(
          BleOpcode.setPairingCode,
          2,
          token,
          payload: BleProtocol.encodePairingCode('654321'),
        ),
      );
      final opening = frame(BleOpcode.openTransfer, 3, token);
      expect(
        BleProtocol.decodeEvent(await exchange(link, opening)).result,
        BleResult.ok,
      );
      expect(link.transferWindowOpen, isTrue);
      expect(
        BleProtocol.decodeEvent(
          await exchange(link, frame(BleOpcode.openTransfer, 4, token)),
        ).result,
        BleResult.busy,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        BleProtocol.decodeEvent(await exchange(link, opening)).result,
        BleResult.ok,
      );
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(link.transferWindowOpen, isFalse);
      expect(link.pairingCode, 654321);
      expect(link.ownerIdentityUnchanged, isTrue);
      expect(
        link.acceptedCommands.where(
          (bytes) => bytes[1] == BleOpcode.openTransfer.value,
        ),
        hasLength(1),
      );
      await link.dispose();
    },
  );

  test(
    'pairing code cannot change until the transfer window is cancelled',
    () async {
      final link = FakeBleLink(sharedPairingSupported: false);
      await link.connect('synthetic');
      final claim = BleProtocol.decodeEvent(
        await exchange(link, frame(BleOpcode.claim, 1, 0)),
      );
      final token = claim.token;
      await exchange(
        link,
        frame(
          BleOpcode.setPairingCode,
          2,
          token,
          payload: BleProtocol.encodePairingCode('654321'),
        ),
      );
      expect(
        BleProtocol.decodeEvent(
          await exchange(link, frame(BleOpcode.openTransfer, 3, token)),
        ).result,
        BleResult.ok,
      );
      expect(
        BleProtocol.decodeEvent(
          await exchange(
            link,
            frame(
              BleOpcode.setPairingCode,
              4,
              token,
              payload: BleProtocol.encodePairingCode('765432'),
            ),
          ),
        ).result,
        BleResult.busy,
      );
      expect(link.pairingCode, 654321);
      expect(
        BleProtocol.decodeEvent(
          await exchange(link, frame(BleOpcode.cancelTransfer, 5, token)),
        ).result,
        BleResult.ok,
      );
      expect(
        BleProtocol.decodeEvent(
          await exchange(
            link,
            frame(
              BleOpcode.setPairingCode,
              6,
              token,
              payload: BleProtocol.encodePairingCode('765432'),
            ),
          ),
        ).result,
        BleResult.ok,
      );
      expect(link.pairingCode, 765432);
      expect(link.transferWindowOpen, isFalse);
      await link.dispose();
    },
  );
  test('retries byte-identical command after lost business ACK', () async {
    final link = FakeBleLink(dropNextReplies: 1);
    final session = DeviceSession(
      link,
      commandTimeout: const Duration(milliseconds: 25),
      maxRetries: 2,
    );
    await session.connect('synthetic');
    expect(link.writes.length, 2);
    expect(link.writes[0], link.writes[1]);
    await session.disconnect();
    await session.dispose();
    await link.dispose();
  });
  test(
    'CLAIM retries the identical seq 1 while subscription setup races',
    () async {
      final link = FakeBleLink()
        ..subscriptionDelay = const Duration(milliseconds: 25);
      final session = DeviceSession(
        link,
        commandTimeout: const Duration(milliseconds: 100),
        maxRetries: 2,
      );
      await session.connect('synthetic');
      expect(link.writes.length, 2);
      expect(byteHex(link.writes[0]), byteHex(link.writes[1]));
      expect(session.snapshot.phase, DeviceSessionPhase.readyPaused);
      await session.disconnect();
      await session.dispose();
      await link.dispose();
    },
  );
  test(
    'exhausted ACK retries disconnect and preserve identical bytes',
    () async {
      final link = FakeBleLink(dropNextReplies: 4);
      final session = DeviceSession(
        link,
        commandTimeout: const Duration(milliseconds: 15),
        maxRetries: 3,
      );
      await expectLater(
        session.connect('synthetic'),
        throwsA(isA<TimeoutException>()),
      );
      expect(link.writes.length, 4);
      expect(link.writes.map(byteHex).toSet().length, 1);
      expect(link.currentState, BleLinkState.disconnected);
      await session.dispose();
      await link.dispose();
    },
  );
  test('does not allow targets until ARM', () async {
    final link = FakeBleLink();
    final session = DeviceSession(
      link,
      commandTimeout: const Duration(milliseconds: 25),
    );
    await session.connect('synthetic');
    await expectLater(
      session.setTarget(ch1: 1500, ch2: 1500, ch3: 1500),
      throwsStateError,
    );
    await session.disconnect();
    await session.dispose();
    await link.dispose();
  });
  test(
    'cancelPendingTargets invalidates not-yet-written preset frames',
    () async {
      final link = FakeBleLink();
      final session = DeviceSession(
        link,
        commandTimeout: const Duration(milliseconds: 200),
      );
      await session.connect('synthetic');
      await session.arm();
      link.writeDelay = const Duration(milliseconds: 30);
      final first = session.setTarget(
        ch1: 1510,
        ch2: 1600,
        ch3: 1700,
        latestOnly: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final queued = session.setTarget(
        ch1: 1520,
        ch2: 1600,
        ch3: 1700,
        latestOnly: false,
      );
      session.cancelPendingTargets();
      await first;
      await expectLater(queued, throwsA(isA<TargetCancelledException>()));
      expect(link.writes.where((f) => f[1] == 2).length, 1);
      await session.disconnect();
      await session.dispose();
      await link.dispose();
    },
  );

  test(
    'latest-only targets have one pending slot and enforce advertised 20 Hz',
    () async {
      final link = FakeBleLink();
      final session = DeviceSession(
        link,
        commandTimeout: const Duration(milliseconds: 100),
      );
      await session.connect('synthetic');
      await session.arm();
      final a = session.setTarget(ch1: 1510, ch2: 1600, ch3: 1700);
      final b = session.setTarget(ch1: 1520, ch2: 1600, ch3: 1700);
      final c = session.setTarget(ch1: 1530, ch2: 1600, ch3: 1700);
      await expectLater(a, throwsA(isA<TargetCancelledException>()));
      await expectLater(b, throwsA(isA<TargetCancelledException>()));
      await c;
      expect(link.acceptedTargetSubmissions, 1);
      final watch = Stopwatch()..start();
      await session.setTarget(ch1: 1540, ch2: 1600, ch3: 1700);
      expect(
        watch.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 40)),
      );
      await session.disconnect();
      await session.dispose();
      await link.dispose();
    },
  );

  test('continuous target updates do not starve keepalive', () async {
    final link = FakeBleLink();
    final session = DeviceSession(
      link,
      commandTimeout: const Duration(milliseconds: 150),
    );
    await session.connect('synthetic');
    await session.arm();
    var next = 1500;
    final ticker = Timer.periodic(const Duration(milliseconds: 2), (_) {
      next = next == 1500 ? 1700 : 1500;
      session
          .setTarget(ch1: next, ch2: 1600, ch3: 1700)
          .catchError((Object _) {});
    });
    await Future<void>.delayed(const Duration(milliseconds: 2300));
    ticker.cancel();
    expect(
      link.acceptedCommands.any((b) => b[1] == BleOpcode.keepalive.value),
      isTrue,
    );
    await session.disconnect();
    await session.dispose();
    await link.dispose();
  });

  test('periodic StateSnapshot refreshes last-commanded channels', () async {
    final link = FakeBleLink();
    final session = DeviceSession(
      link,
      commandTimeout: const Duration(milliseconds: 100),
    );
    await session.connect('synthetic');
    await session.arm();
    await session.setTarget(ch1: 1800, ch2: 1600, ch3: 1700, latestOnly: false);
    expect(session.snapshot.state?.channels, [1500, 1500, 1500]);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(session.snapshot.state?.channels, [1800, 1600, 1700]);
    await session.disconnect();
    await session.dispose();
    await link.dispose();
  });

  test('lost target ACK followed by HALT cannot cause a stale retry', () async {
    final link = FakeBleLink();
    final session = DeviceSession(
      link,
      commandTimeout: const Duration(milliseconds: 40),
      maxRetries: 3,
    );
    await session.connect('synthetic');
    await session.arm();
    link.dropNextReplies = 1;
    final target = session.setTarget(
      ch1: 1800,
      ch2: 1600,
      ch3: 1700,
      latestOnly: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    session.cancelPendingTargets();
    final halted = session.halt();
    await expectLater(target, throwsA(isA<TargetCancelledException>()));
    await halted;
    final targetWrites = link.writes
        .where((b) => b[1] == BleOpcode.setTarget.value)
        .toList();
    expect(targetWrites.length, 1);
    expect(link.snapshotTokenOverride, isNull);
    expect(
      session.snapshot.state?.lastAppliedSequence,
      greaterThan(BleProtocol.decodeControlFrame(targetWrites.single).sequence),
    );
    await session.disconnect();
    await session.dispose();
    await link.dispose();
  });

  test(
    'heartbeat retries and replies arrive before GATT write future completes',
    () async {
      final peer = FakeBleLink();
      final link = AckBeforeWriteCompletes(peer);
      final session = DeviceSession(
        link,
        commandTimeout: const Duration(milliseconds: 100),
      );
      await session.connect('synthetic');
      await session.arm();
      expect(session.snapshot.isArmed, isTrue);
      await session.disconnect();
      await session.dispose();
      await peer.dispose();
    },
  );

  test(
    'malformed and wrong-token async events are ignored without corrupting snapshot',
    () async {
      final link = FakeBleLink();
      final session = DeviceSession(
        link,
        commandTimeout: const Duration(milliseconds: 100),
      );
      await session.connect('synthetic');
      await session.arm();
      final before = session.snapshot.state;
      link.emitEvent([1, 0xe0, 0, 0]);
      link.emitEvent(
        BleProtocol.encodeEvent(
          opcode: 0xe0,
          sequence: 0,
          token: 0x99999999,
          result: BleResult.ok,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(session.snapshot.phase, DeviceSessionPhase.armed);
      expect(session.snapshot.state?.channels, before?.channels);
      expect(session.snapshot.lastError, isNull);
      await session.disconnect();
      await session.dispose();
      await link.dispose();
    },
  );

  test('sequence reaches u32 max without wrapping to zero', () async {
    final link = FakeBleLink();
    final session = DeviceSession.testSeeded(
      link,
      nextSequence: 0xffffffff,
      commandTimeout: const Duration(milliseconds: 100),
    );
    await session.connect('synthetic');
    await session.arm();
    expect(link.writes.last[2], 0xff);
    expect(link.writes.last[3], 0xff);
    expect(link.writes.last[4], 0xff);
    expect(link.writes.last[5], 0xff);
    await expectLater(
      session.setTarget(ch1: 1600, ch2: 1600, ch3: 1700),
      throwsStateError,
    );
    expect(
      link.writes.where((b) => b[1] == BleOpcode.setTarget.value),
      isEmpty,
    );
    await session.disconnect();
    await session.dispose();
    await link.dispose();
  });

  test('wrong secure identity is rejected before CLAIM', () async {
    final link = FakeBleLink();
    final session = DeviceSession(
      link,
      commandTimeout: const Duration(milliseconds: 100),
    );
    await expectLater(
      session.connect(
        'synthetic',
        expectedIdentity: 'ffffffffffffffffffffffffffffffff',
      ),
      throwsStateError,
    );
    expect(link.writes, isEmpty);
    expect(link.currentState, BleLinkState.disconnected);
    await session.dispose();
    await link.dispose();
  });

  test(
    'StateSnapshot token mismatch fails closed before exposing ready session',
    () async {
      final link = FakeBleLink()..snapshotTokenOverride = 0x99999999;
      final session = DeviceSession(
        link,
        commandTimeout: const Duration(milliseconds: 100),
      );
      await expectLater(session.connect('synthetic'), throwsStateError);
      expect(session.snapshot.isConnected, isFalse);
      expect(link.currentState, BleLinkState.disconnected);
      await session.dispose();
      await link.dispose();
    },
  );

  test(
    'BLE disconnect during an in-flight connect invalidates its completion',
    () async {
      final link = FakeBleLink()
        ..connectDelay = const Duration(milliseconds: 40);
      final session = DeviceSession(
        link,
        commandTimeout: const Duration(milliseconds: 100),
      );
      final connecting = session.connect('synthetic');
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await session.disconnect();
      await expectLater(connecting, throwsStateError);
      expect(session.snapshot.phase, DeviceSessionPhase.disconnected);
      await session.dispose();
      await link.dispose();
    },
  );

  test(
    'cached duplicate is idempotent, conflicting same sequence is rejected',
    () async {
      final link = FakeBleLink();
      await link.connect('synthetic');
      final claim = frame(BleOpcode.claim, 1, 0);
      final claimReply = await exchange(link, claim);
      final token = BleProtocol.decodeEvent(claimReply).token;
      await exchange(link, frame(BleOpcode.arm, 2, token));
      final set = frame(
        BleOpcode.setTarget,
        3,
        token,
        payload: BleProtocol.encodeSetTarget(
          ch1: 1500,
          ch2: 1600,
          ch3: 1700,
          transitionMs: 200,
        ),
      );
      final first = await exchange(link, set);
      final replay = await exchange(link, set);
      expect(replay, first);
      expect(link.acceptedTargetSubmissions, 1);
      final changed = frame(
        BleOpcode.setTarget,
        3,
        token,
        payload: BleProtocol.encodeSetTarget(
          ch1: 1510,
          ch2: 1600,
          ch3: 1700,
          transitionMs: 200,
        ),
      );
      expect(
        BleProtocol.decodeEvent(await exchange(link, changed)).result,
        BleResult.sequenceConflict,
      );
      expect(link.acceptedTargetSubmissions, 1);
      await link.disconnect();
      await link.dispose();
    },
  );

  test(
    'duplicate replays do not extend the lease; evicted frames remain old',
    () async {
      final link = FakeBleLink(leaseTimeout: const Duration(milliseconds: 300));
      await link.connect('synthetic');
      final claim = frame(BleOpcode.claim, 1, 0);
      final token = BleProtocol.decodeEvent(await exchange(link, claim)).token;
      await exchange(link, frame(BleOpcode.arm, 2, token));
      final set = frame(
        BleOpcode.setTarget,
        3,
        token,
        payload: BleProtocol.encodeSetTarget(
          ch1: 1500,
          ch2: 1600,
          ch3: 1700,
          transitionMs: 200,
        ),
      );
      await exchange(link, set);
      await Future<void>.delayed(const Duration(milliseconds: 180));
      await exchange(link, set);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(link.currentToken, 0);

      await link.disconnect();
      await link.connect('synthetic');
      final newToken = BleProtocol.decodeEvent(
        await exchange(link, claim),
      ).token;
      await exchange(link, frame(BleOpcode.arm, 2, newToken));
      final sequence3 = frame(
        BleOpcode.setTarget,
        3,
        newToken,
        payload: BleProtocol.encodeSetTarget(
          ch1: 1500,
          ch2: 1600,
          ch3: 1700,
          transitionMs: 200,
        ),
      );
      await exchange(link, sequence3);
      for (var seq = 4; seq <= 21; seq++) {
        await exchange(link, frame(BleOpcode.keepalive, seq, newToken));
      }
      expect(
        BleProtocol.decodeEvent(await exchange(link, sequence3)).result,
        BleResult.oldSequence,
      );
      await link.disconnect();
      await link.dispose();
    },
  );

  test('RELEASE cannot be resurrected by replaying old CLAIM', () async {
    final link = FakeBleLink();
    await link.connect('synthetic');
    final claim = frame(BleOpcode.claim, 1, 0);
    final token = BleProtocol.decodeEvent(await exchange(link, claim)).token;
    await exchange(link, frame(BleOpcode.arm, 2, token));
    await exchange(link, frame(BleOpcode.release, 3, token));
    expect(
      BleProtocol.decodeEvent(await exchange(link, claim)).result,
      BleResult.badSession,
    );
    expect(link.currentToken, 0);
    await link.disconnect();
    await link.dispose();
  });

  test('lease expires despite malformed traffic and status polling', () async {
    final link = FakeBleLink(leaseTimeout: const Duration(milliseconds: 80));
    await link.connect('synthetic');
    final claim = frame(BleOpcode.claim, 1, 0);
    final token = BleProtocol.decodeEvent(await exchange(link, claim)).token;
    await exchange(link, frame(BleOpcode.getStatus, 2, token));
    for (var i = 0; i < 4; i++) {
      await link.write(
        BleProtocol.controlRxUuid,
        frame(BleOpcode.setTarget, 3 + i, token).sublist(0, 19),
      );
      await Future<void>.delayed(const Duration(milliseconds: 12));
    }
    await Future<void>.delayed(const Duration(milliseconds: 35));
    expect(link.currentToken, 0);
    expect(link.connectionState, isNotNull);
    await link.dispose();
  });

  test('NOT_CONFIGURED does not consume the sequence or disconnect', () async {
    final link = FakeBleLink(configured: false);
    final session = DeviceSession(
      link,
      commandTimeout: const Duration(milliseconds: 100),
    );
    await session.connect('synthetic');
    await expectLater(
      session.arm(),
      throwsA(
        isA<BleCommandRejected>().having(
          (e) => e.result,
          'result',
          BleResult.notConfigured,
        ),
      ),
    );
    expect(session.snapshot.isConnected, isTrue);
    expect(session.snapshot.state?.validChannelMask, 0);
    expect(link.writes.where((b) => b[1] == BleOpcode.arm.value).length, 1);
    await session.disconnect();
    await session.dispose();
    await link.dispose();
  });

  test(
    'firmware token loss is fatal and invalidates the connected session',
    () async {
      final link = FakeBleLink();
      final session = DeviceSession(
        link,
        commandTimeout: const Duration(milliseconds: 100),
      );
      await session.connect('synthetic');
      link.revokeSession();
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      expect(session.snapshot.isConnected, isFalse);
      expect(link.currentState, BleLinkState.disconnected);
      await session.dispose();
      await link.dispose();
    },
  );

  test(
    'notification stream failure disconnects instead of preserving ready state',
    () async {
      final link = FakeBleLink();
      final session = DeviceSession(
        link,
        commandTimeout: const Duration(milliseconds: 100),
      );
      await session.connect('synthetic');
      link.failNotifications(StateError('notify stream failed'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(session.snapshot.isConnected, isFalse);
      expect(link.currentState, BleLinkState.disconnected);
      await session.dispose();
      await link.dispose();
    },
  );
}
