import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:satori_manager/core/legacy_udp_engine.dart';
import 'package:satori_manager/core/protocol.dart';
import 'package:satori_manager/infrastructure/udp_transport.dart';

class FakeTransport implements Transport {
  PacketHandler? handler;
  final sent = <String>[];
  @override
  Future<void> open(
    PacketHandler onPacket,
    void Function(String) onError,
  ) async {
    handler = onPacket;
  }

  @override
  void send(Endpoint endpoint, String message) {
    sent.add('$endpoint $message');
  }

  @override
  void close() {}
  void reply(Endpoint source, String message) =>
      handler!(source, utf8.encode(message));
}

class FakeTimer implements Timer {
  FakeTimer(this.duration, this.callback);
  final Duration duration;
  final void Function() callback;
  bool _active = true;
  @override
  bool get isActive => _active;
  @override
  void cancel() => _active = false;
  void fire() {
    if (_active) {
      _active = false;
      callback();
    }
  }

  @override
  int get tick => 0;
}

class Harness {
  final transport = FakeTransport();
  final timers = <FakeTimer>[];
  DateTime time = DateTime.utc(2026);
  late final engine = ControlEngine(
    transport,
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
    schedule: (delay, callback) {
      final timer = FakeTimer(delay, callback);
      timers.add(timer);
      return timer;
    },
  );
  static const device = Endpoint('192.0.2.2', 8888);
  Future<void> connect() async {
    await engine.open();
    engine.discover(host: device.host);
    transport.reply(device, 'SatoriEye_DISCOVERY_RESPONSE,77,SIMULATOR');
    engine.select(
      device,
      isSimulator: true,
      profile: SafetyProfile.simulator(),
    );
  }

  void fireNext() {
    final index = timers.indexWhere((timer) => timer.isActive);
    if (index < 0) throw StateError('no pending timer');
    timers[index].fire();
  }
}

void main() {
  test(
    'selected endpoint only; duplicate discovery does not reset mode',
    () async {
      final h = Harness();
      await h.connect();
      h.engine.setAutoRotate(true);
      h.transport.reply(Harness.device, 'SatoriEye_DISCOVERY_RESPONSE,50');
      h.transport.reply(
        const Endpoint('192.0.2.3', 8888),
        'SatoriEye_HEARTBEAT_RESPONSE,30',
      );
      expect(h.engine.mode, 'auto');
      expect(h.engine.battery, 77);
      expect(h.engine.discovered, [Harness.device]);
      h.engine.dispose();
    },
  );

  test('real discovery cannot bypass safe range with simulator flag', () async {
    final h = Harness();
    await h.engine.open();
    h.engine.discover(host: Harness.device.host);
    h.transport.reply(Harness.device, 'SatoriEye_DISCOVERY_RESPONSE,77');
    expect(
      () => h.engine.select(
        Harness.device,
        isSimulator: true,
        profile: SafetyProfile.simulator(),
      ),
      throwsStateError,
    );
    h.engine.dispose();
  });

  test(
    'frame delay is independent of smooth duration; stop cancels remainder',
    () async {
      final h = Harness();
      await h.connect();
      h.engine.play('wink');
      expect(h.timers.last.duration, const Duration(milliseconds: 450));
      expect(
        h.transport.sent.last,
        endsWith('SMOOTH:CH1:1500CH2:1500CH3:500MS:200'),
      );
      h.engine.stopMotion();
      final before = h.transport.sent.length;
      h.timers.last.fire();
      expect(h.transport.sent.length, before);
      expect(h.engine.playback, 'idle');
      h.engine.dispose();
    },
  );

  test(
    'lost session only retries original endpoint and resumes stopped',
    () async {
      final h = Harness();
      await h.connect();
      h.engine.setAutoRotate(true);
      h.time = h.time.add(const Duration(seconds: 60));
      h.fireNext();
      expect(h.engine.connection, 'reconnecting');
      expect(h.engine.autoRotate, false);
      expect(h.transport.sent.last, '${Harness.device} ${Protocol.heartbeat}');
      h.transport.reply(
        const Endpoint('192.0.2.3', 8888),
        'SatoriEye_HEARTBEAT_RESPONSE',
      );
      expect(h.engine.connection, 'reconnecting');
      h.transport.reply(Harness.device, 'SatoriEye_HEARTBEAT_RESPONSE,77');
      expect(h.engine.connection, 'connected');
      expect(h.engine.autoRotate, false);
      expect(h.engine.snapshot()['battery'], 77);
      h.engine.disconnect();
      expect(h.engine.connection, 'disconnected');
      expect(h.engine.snapshot()['endpoint'], isNull);
      h.engine.dispose();
    },
  );

  test(
    'discovery expires with no results; intentional disconnect does not reconnect',
    () async {
      final h = Harness();
      await h.engine.open();
      h.engine.discover(host: Harness.device.host);
      h.timers.last.fire();
      expect(h.engine.connection, 'no_results');
      h.engine.disconnect();
      final before = h.transport.sent.length;
      h.time = h.time.add(const Duration(minutes: 3));
      h.fireNext();
      expect(h.engine.connection, 'disconnected');
      expect(h.transport.sent.length, before);
      h.engine.dispose();
    },
  );

  test(
    'reconnect stops after five probes without playing missed frames',
    () async {
      final h = Harness();
      await h.connect();
      h.engine.play('wink');
      h.time = h.time.add(const Duration(seconds: 60));
      h.fireNext();
      for (var i = 0; i < 5; i++) {
        final retry = h.timers.firstWhere(
          (v) => v.isActive && v.duration == const Duration(seconds: 10),
        );
        retry.fire();
      }
      expect(h.engine.connection, 'failed');
      expect(h.engine.playback, 'idle');
      expect(
        h.transport.sent.where((v) => v.endsWith(Protocol.heartbeat)).length,
        5,
      );
      h.engine.dispose();
    },
  );

  test('manual takeover cancels playback and merges channels', () async {
    final h = Harness();
    await h.connect();
    h.engine.play('wink');
    h.engine.setManual([.4, .6, .5]);
    expect(h.engine.playback, 'idle');
    expect(h.transport.sent.last, endsWith('CH1:1300CH2:1700CH3:1500'));
    h.engine.dispose();
  });

  test('joystick release restores CH1/CH2 and preserves CH3', () async {
    final h = Harness();
    await h.connect();
    h.engine.setManual([.5, .5, .8]);
    h.engine.play('wink');
    h.engine.setManual([.2, .7, -1]);
    expect(h.engine.playback, 'idle');
    expect(h.transport.sent.last, endsWith('CH1:900CH2:1900CH3:500'));
    h.engine.setManual([.5, .5, -1]);
    expect(h.transport.sent.last, endsWith('CH1:1500CH2:1500CH3:500'));
    expect(() => h.engine.setManual([.5, .5, -2]), throwsFormatException);
    h.engine.dispose();
  });

  test('automatic wink retains current rotation channels', () async {
    final h = Harness();
    await h.connect();
    h.engine.setAutoRotate(true);
    final rotation = List<int>.from(h.engine.target);
    h.engine.setAutoWink(true);
    h.timers.last.fire();
    expect(h.engine.target.take(2), rotation.take(2));
    expect(h.engine.target[2], 500);
    expect(
      h.transport.sent.last,
      contains('CH1:${rotation[0]}CH2:${rotation[1]}CH3:500'),
    );
    h.engine.dispose();
  });
}
