// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

void main() {
  final directory = Directory('../docs/protocol');
  final manifest =
      jsonDecode(
            File('${directory.path}/compatibility.json').readAsStringSync(),
          )
          as Map;
  for (final entry in (manifest['files'] as Map).entries) {
    final bytes = File('${directory.path}/${entry.key}').readAsBytesSync();
    if (sha256.convert(bytes).toString() != entry.value) {
      throw StateError('BLE contract drift: ${entry.key}');
    }
    final sourceName = entry.key == 'satori-ble-v1.md'
        ? 'SatoriEye_BLE_Protocol_v1.md'
        : entry.key;
    final source = File('../../ESP-3RDEYE/docs/ble/v1/$sourceName');
    if (source.existsSync() &&
        sha256.convert(source.readAsBytesSync()).toString() != entry.value) {
      throw StateError('Firmware/App contract mismatch: ${entry.key}');
    }
  }
  print('BLE document and vectors match compatibility.json.');
}
