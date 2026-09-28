import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:satori_manager/core/control_engine.dart';
import 'package:satori_manager/core/protocol.dart';
import 'package:satori_manager/infrastructure/udp_transport.dart';

void main() {
  test('real UDP discovery, response, control and disconnect', () async {
    final server = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      8888,
    );
    final messages = <String>[];
    final received = Completer<void>();
    final subscription = server.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? packet;
      while ((packet = server.receive()) != null) {
        final message = utf8.decode(packet!.data);
        messages.add(message);
        if (message == Protocol.discovery) {
          server.send(
            utf8.encode('SatoriEye_DISCOVERY_RESPONSE,77,SIMULATOR'),
            packet.address,
            packet.port,
          );
        }
        if (message == Protocol.disconnect && !received.isCompleted) {
          received.complete();
        }
      }
    });
    final engine = ControlEngine(UdpTransport(), {});
    try {
      await engine.open();
      engine.discover(host: '127.0.0.1');
      await engine.updates
          .firstWhere((snapshot) => (snapshot['discovered'] as List).isNotEmpty)
          .timeout(const Duration(seconds: 2));
      engine.select(
        const Endpoint('127.0.0.1', 8888),
        isSimulator: true,
        profile: SafetyProfile.simulator(),
      );
      engine.setManual([.5, .5, .5]);
      engine.setManual([.2, .7, -1]);
      engine.setManual([.5, .5, -1]);
      engine.disconnect();
      await received.future.timeout(const Duration(seconds: 2));
      expect(messages, contains('CH1:1500CH2:1500CH3:1500'));
      expect(messages, contains('CH1:900CH2:1900CH3:1500'));
      expect(messages.first, Protocol.discovery);
      expect(messages.last, Protocol.disconnect);
    } finally {
      engine.dispose();
      await subscription.cancel();
      server.close();
    }
  });
}
