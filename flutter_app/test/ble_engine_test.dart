import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:satori_manager/core/ble_protocol.dart';
import 'package:satori_manager/core/control_engine.dart';
import 'package:satori_manager/core/device_session.dart';
import 'package:satori_manager/core/protocol.dart';
import 'package:satori_manager/core/safety_limits.dart';
import 'package:satori_manager/infrastructure/fake_ble_link.dart';

class TestTimer implements Timer {
  TestTimer(this.delay, this.callback);
  final Duration delay;
  final void Function() callback;
  bool active = true;
  @override
  bool get isActive => active;
  @override
  int get tick => 0;
  @override
  void cancel() => active = false;
  void fire() {
    if (active) {
      active = false;
      callback();
    }
  }
}

class Harness {
  Harness({FakeBleLink? link}) : link = link ?? FakeBleLink();

  final FakeBleLink link;
  late final session = DeviceSession(link);
  final timers = <TestTimer>[];
  Duration time = Duration.zero;
  late final engine = ControlEngine(
    session,
    {
      'wink': [
        ActionFrame([-1, -1, 0], const Duration(milliseconds: 450)),
        ActionFrame([-1, -1, 1], const Duration(milliseconds: 200)),
      ],
      'wink2': [
        ActionFrame([-1, -1, 0], const Duration(milliseconds: 200)),
        ActionFrame([-1, -1, 1], const Duration(milliseconds: 200)),
      ],
    },
    clock: () => time,
    schedule: (duration, callback) {
      final timer = TestTimer(duration, callback);
      timers.add(timer);
      return timer;
    },
  );
  Future<void> connect({SafetyLimits? limits}) => engine.connect(
    'fake',
    limits: limits ?? SafetyLimits([1000, 1100, 1200], [2000, 1900, 1800]),
  );
  List<BleControlFrame> get targets => link.writes
      .map(BleProtocol.decodeControlFrame)
      .where((f) => f.opcode == BleOpcode.setTarget.value)
      .toList();
  int get armCount => link.writes
      .map(BleProtocol.decodeControlFrame)
      .where((f) => f.opcode == BleOpcode.arm.value)
      .length;
  Future<void> flush() =>
      Future<void>.delayed(const Duration(milliseconds: 80));
  Future<void> close() async {
    await engine.dispose();
    await session.dispose();
    await link.dispose();
  }
}

void main() {
  test('connect auto-ARMs known safe startup channels', () async {
    final h = Harness();
    addTearDown(h.close);
    await h.connect();
    expect(h.engine.connection, 'connected');
    expect(h.engine.outputAuthorized, true);
    expect(h.engine.target, h.session.snapshot.state!.channels);
    await h.engine.arm();
    expect(h.engine.target, [1500, 1500, 1500]);
    await h.engine.setManual([0, 1, -1]);
    expect(h.engine.target, [1000, 1900, 1500]);
    final manualPayload = h.targets.last.payload;
    expect(manualPayload[6] | manualPayload[7] << 8, 50);
  });

  test(
    'preset duration is independent of 200ms transition; stop cancels remainder',
    () async {
      final h = Harness();
      addTearDown(h.close);
      await h.connect();
      await h.engine.arm();
      h.engine.play('wink');
      await h.flush();
      expect(h.targets.length, 1);
      expect(
        h.targets.single.payload[6] | h.targets.single.payload[7] << 8,
        200,
      );
      final timer = h.timers.last;
      expect(timer.delay, const Duration(milliseconds: 450));
      await h.engine.stopMotion();
      timer.fire();
      await h.flush();
      expect(h.targets.length, 1);
      expect(h.engine.playback, 'idle');
      expect(h.engine.outputAuthorized, false);
    },
  );

  test('late preset cancels instead of replaying accumulated frames', () async {
    final h = Harness();
    addTearDown(h.close);
    await h.connect();
    await h.engine.arm();
    h.engine.play('wink');
    await h.flush();
    h.time = const Duration(milliseconds: 700);
    h.timers.last.fire();
    await h.flush();
    expect(h.targets.length, 1);
    expect(h.engine.playback, 'idle');
    expect(h.engine.error, contains('过期'));
  });

  test(
    'manual takeover invalidates preset timers and preserves untouched channels',
    () async {
      final h = Harness();
      addTearDown(h.close);
      await h.connect();
      await h.engine.arm();
      h.engine.play('wink');
      await h.flush();
      final oldTimer = h.timers.last;
      await h.engine.setManual([.3, .7, -1]);
      final count = h.targets.length;
      oldTimer.fire();
      await h.flush();
      expect(h.targets.length, count);
      expect(h.engine.target, [1100, 1900, 1200]);
    },
  );

  test(
    'disconnect recovery freshly auto-ARMs without replaying old actions',
    () async {
      final h = Harness();
      addTearDown(h.close);
      await h.connect();
      await h.engine.arm();
      h.engine.setAutoRotate(true);
      await h.flush();
      await h.link.disconnect();
      await h.flush();
      expect(h.engine.connection, 'reconnecting');
      expect(h.engine.autoRotate, false);
      expect(h.engine.outputAuthorized, false);
      final retry = h.timers.last;
      expect(retry.delay, const Duration(seconds: 1));
      final before = h.targets.length;
      final oldArmCount = h.armCount;
      retry.fire();
      await h.flush();
      expect(h.engine.connection, 'connected');
      expect(h.engine.target, h.session.snapshot.state!.channels);
      expect(h.engine.outputAuthorized, true);
      expect(h.targets.length, before);
      expect(h.armCount, oldArmCount + 1);
    },
  );

  test('pause during reconnect backoff persists when retry succeeds', () async {
    final h = Harness();
    addTearDown(h.close);
    await h.connect();
    final armCount = h.armCount;
    await h.link.disconnect();
    await h.flush();
    expect(h.engine.connection, 'reconnecting');

    await h.engine.stopMotion();
    h.timers.last.fire();
    await h.flush();

    expect(h.engine.connection, 'connected');
    expect(h.engine.outputAuthorized, false);
    expect(h.armCount, armCount);
  });

  test('pause survives a failed reconnect attempt and later retry', () async {
    final shared = FakeBleSharedDevice();
    expect(shared.pairPhone('engine-phone', '123456'), isTrue);
    expect(shared.pairPhone('blocking-phone', '123456'), isTrue);
    final h = Harness(
      link: FakeBleLink(sharedDevice: shared, phoneId: 'engine-phone'),
    );
    final blocker = FakeBleLink(
      sharedDevice: shared,
      phoneId: 'blocking-phone',
    );
    addTearDown(() async {
      await h.close();
      await blocker.dispose();
    });
    await h.connect();
    final armCount = h.armCount;
    await h.link.disconnect();
    await h.flush();
    await blocker.connect('fake');

    h.timers.last.fire();
    await h.flush();
    expect(h.engine.connection, 'reconnecting');
    expect(h.timers.last.delay, const Duration(seconds: 2));

    await h.engine.stopMotion();
    await blocker.disconnect();
    h.timers.last.fire();
    await h.flush();

    expect(h.engine.connection, 'connected');
    expect(h.engine.outputAuthorized, false);
    expect(h.armCount, armCount);
  });

  test(
    'pause racing ARM cannot reauthorize output from a late completion',
    () async {
      final h = Harness();
      addTearDown(h.close);
      await h.connect();
      await h.engine.stopMotion();
      h.link.writeDelay = const Duration(milliseconds: 30);
      final oldArmCount = h.armCount;
      final arm = h.engine.arm();
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final stop = h.engine.stopMotion();
      await Future.wait([arm, stop]);
      expect(h.engine.outputAuthorized, false);
      expect(h.targets, isEmpty);
      expect(h.armCount, oldArmCount + 1);
      expect(h.link.writes.last[1], BleOpcode.halt.value);
    },
  );

  test(
    'pause cancels ARM queued behind a slow command before transmission',
    () async {
      final h = Harness();
      addTearDown(h.close);
      await h.connect();
      await h.engine.stopMotion();
      h.link.writeDelay = const Duration(milliseconds: 35);
      final slowHalt = h.session.halt();
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final oldArmCount = h.armCount;
      final configure = h.engine.arm();
      final cancelledArm = expectLater(
        configure,
        throwsA(isA<TargetCancelledException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final stop = h.engine.stopMotion();
      await Future.wait([slowHalt, stop]);
      await cancelledArm;
      expect(h.armCount, oldArmCount);
      expect(h.engine.outputAuthorized, false);
      expect(h.link.writes.last[1], BleOpcode.halt.value);
    },
  );

  test(
    'unconfigured device remains connected and reports paused reason',
    () async {
      final link = FakeBleLink(configured: false);
      final session = DeviceSession(link);
      final engine = ControlEngine(session, const {});
      addTearDown(() async {
        await engine.dispose();
        await link.dispose();
      });
      await engine.connect(
        'fake',
        limits: SafetyLimits([1000, 1100, 1200], [2000, 1900, 1800]),
      );
      expect(engine.connection, 'connected');
      expect(engine.outputAuthorized, false);
      expect(engine.error, contains('尚未配置'));
    },
  );

  test(
    'no saved safety limits uses the built-in Satori C3 logical range',
    () async {
      final h = Harness();
      addTearDown(h.close);
      await h.engine.connect('fake');
      expect(h.engine.outputAuthorized, true);
      expect(h.engine.safety?.minimum, [500, 500, 500]);
      expect(h.engine.safety?.maximum, [2500, 2500, 2500]);
      expect(h.engine.target, [1500, 1500, 1500]);
    },
  );

  test('pause during connecting prevents late automatic ARM', () async {
    final link = FakeBleLink(connectDelay: const Duration(milliseconds: 25));
    final session = DeviceSession(link);
    final engine = ControlEngine(session, const {});
    addTearDown(() async {
      await engine.dispose();
      await link.dispose();
    });
    final connecting = engine.connect(
      'fake',
      limits: SafetyLimits([1000, 1100, 1200], [2000, 1900, 1800]),
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await engine.stopMotion();
    await connecting;
    expect(engine.connection, 'connected');
    expect(engine.outputAuthorized, false);
    expect(
      link.writes.map(BleProtocol.decodeControlFrame),
      isNot(
        contains(
          predicate<BleControlFrame>((f) => f.opcode == BleOpcode.arm.value),
        ),
      ),
    );
  });

  test(
    'disconnect during auto-ARM never leaves a false connected snapshot',
    () async {
      final link = FakeBleLink(writeDelay: const Duration(milliseconds: 3));
      final session = DeviceSession(link);
      final engine = ControlEngine(session, const {});
      final disconnectOnArm = session.snapshots.listen((snapshot) {
        if (snapshot.isArmed) unawaited(link.disconnect());
      });
      addTearDown(() async {
        await disconnectOnArm.cancel();
        await engine.dispose();
        await link.dispose();
      });
      try {
        await engine.connect(
          'fake',
          limits: SafetyLimits([1000, 1100, 1200], [2000, 1900, 1800]),
        );
      } catch (_) {
        // The disconnect may be observed before connect's ARM completion.
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(session.snapshot.isConnected, false);
      expect(engine.connection, isNot('connected'));
      expect(engine.outputAuthorized, false);
    },
  );

  test('wrong saved identity is rejected before acquiring control', () async {
    final h = Harness();
    addTearDown(h.close);
    await expectLater(
      h.engine.connect(
        'fake',
        expectedIdentity: 'ffffffffffffffffffffffffffffffff',
      ),
      throwsStateError,
    );
    expect(h.engine.connection, 'failed');
    expect(h.link.writes, isEmpty);
    expect(h.engine.outputAuthorized, false);
  });
}
