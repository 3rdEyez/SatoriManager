/// A BLE peripheral discovered while the app's owning runtime is scanning.
class BleDiscoveredDevice {
  const BleDiscoveredDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

  /// Platform connection identifier. It is not a stable authorization identity.
  final String id;
  final String name;
  final int rssi;
}
