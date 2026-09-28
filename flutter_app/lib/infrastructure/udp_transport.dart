import 'dart:convert';
import 'dart:io';
import '../core/protocol.dart';

typedef PacketHandler = void Function(Endpoint source, List<int> bytes);

abstract interface class Transport {
  Future<void> open(PacketHandler onPacket, void Function(String) onError);
  void send(Endpoint endpoint, String message);
  void close();
}

class UdpTransport implements Transport {
  UdpTransport({this.port = 8889});
  final int port;
  RawDatagramSocket? _socket;

  @override
  Future<void> open(
    PacketHandler onPacket,
    void Function(String) onError,
  ) async {
    if (_socket != null) return;
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: false,
      );
      _socket = socket;
      socket.broadcastEnabled = true;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? packet;
        while ((packet = socket.receive()) != null) {
          onPacket(Endpoint(packet!.address.address, packet.port), packet.data);
        }
      }, onError: (Object error) => onError('UDP 接收失败：$error'));
    } on SocketException catch (error) {
      throw StateError('无法绑定 UDP $port，请关闭占用该端口的客户端：$error');
    }
  }

  @override
  void send(Endpoint endpoint, String message) {
    final socket = _socket;
    if (socket == null) throw StateError('UDP 未打开');
    final bytes = utf8.encode(message);
    if (socket.send(bytes, InternetAddress(endpoint.host), endpoint.port) !=
        bytes.length) {
      throw StateError('UDP 发送未完成');
    }
  }

  @override
  void close() {
    _socket?.close();
    _socket = null;
  }
}
