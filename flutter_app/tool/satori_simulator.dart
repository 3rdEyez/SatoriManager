import 'dart:convert';
import 'dart:io';
import 'package:satori_manager/core/protocol.dart';

Future<void> main(List<String> args) async {
  final bind = _option(args, '--bind') ?? '0.0.0.0';
  final dropEvery = int.parse(_option(args, '--drop-every') ?? '0');
  final silentAfter = int.tryParse(_option(args, '--silent-after') ?? '');
  final malformed = args.contains('--malformed');
  final battery = int.parse(_option(args, '--battery') ?? '77');
  final socket = await RawDatagramSocket.bind(InternetAddress(bind), 8888);
  socket.broadcastEnabled = true;
  stderr.writeln(
    'SIMULATOR bind=$bind:8888 dropEvery=$dropEvery silentAfter=$silentAfter malformed=$malformed',
  );
  var count = 0;
  socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    Datagram? packet;
    while ((packet = socket.receive()) != null) {
      count++;
      final source = packet!.address;
      final port = packet.port;
      final text = utf8.decode(packet.data, allowMalformed: true);
      stdout.writeln(
        '${DateTime.now().toUtc().toIso8601String()} ${source.address}:$port raw=${packet.data} text=$text',
      );
      if ((dropEvery > 0 && count % dropEvery == 0) ||
          (silentAfter != null && count > silentAfter)) {
        continue;
      }
      final response = switch (text) {
        Protocol.discovery =>
          malformed
              ? 'INVALID_DISCOVERY'
              : 'SatoriEye_DISCOVERY_RESPONSE,$battery,SIMULATOR',
        Protocol.heartbeat =>
          malformed
              ? 'INVALID_HEARTBEAT'
              : 'SatoriEye_HEARTBEAT_RESPONSE,$battery',
        _ => null,
      };
      if (response != null) {
        socket.send(utf8.encode(response), source, port);
        stdout.writeln(
          '${DateTime.now().toUtc().toIso8601String()} reply=$response',
        );
      }
    }
  });
}

String? _option(List<String> args, String name) {
  final index = args.indexOf(name);
  return index >= 0 && index + 1 < args.length ? args[index + 1] : null;
}
