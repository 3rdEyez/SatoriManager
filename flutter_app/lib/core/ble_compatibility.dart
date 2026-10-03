import 'ble_protocol.dart';

/// App and firmware releases use the same major/minor compatibility line.
/// Patch releases may differ without changing pairing or the BLE contract.
class BleCompatibility {
  static const appVersion = '0.2.6';
  static const appMajor = 0;
  static const appMinor = 2;
  static const protocolMajor = 1;
  static const protocolMinor = 2;
  static const protocolVersion = '$protocolMajor.$protocolMinor';

  static String? incompatibility(BleDeviceInfo info) {
    if (info.firmwareMajor != appMajor || info.firmwareMinor != appMinor) {
      return '固件版本 ${info.firmwareVersion} 与应用 $appVersion 不兼容';
    }
    if (info.protocolMajor != protocolMajor ||
        info.protocolMinor != protocolMinor) {
      return 'BLE 协议 ${info.protocolMajor}.${info.protocolMinor} 与应用支持的 $protocolVersion 不兼容';
    }
    if (!info.supportsRequiredCapabilities) {
      return '固件缺少当前应用所需的 BLE 功能';
    }
    return null;
  }
}

class BleVersionMismatch implements Exception {
  const BleVersionMismatch(this.deviceInfo, this.reason);
  final BleDeviceInfo deviceInfo;
  final String reason;

  @override
  String toString() => reason;
}
