import 'dart:async';

import 'package:bluez/bluez.dart';

import '../core/ble_protocol.dart';
import '../core/device_session.dart';
import 'ble_discovery.dart';

/// Linux transport for development diagnostics, backed by the system BlueZ
/// daemon and its configured pairing agent.
class BluezBleLink implements BleLink {
  BluezBleLink({BlueZClient? client}) : _client = client ?? BlueZClient();

  final BlueZClient _client;
  BlueZDevice? _device;
  StreamSubscription<List<String>>? _deviceProperties;
  final StreamController<BleLinkState> _state =
      StreamController<BleLinkState>.broadcast();
  BleLinkState _currentState = BleLinkState.disconnected;
  bool _connectedByThisLink = false;
  bool _initialized = false;

  @override
  Stream<BleLinkState> get connectionState => _state.stream;

  BleLinkState get currentState => _currentState;

  Future<void> _initialize() async {
    if (_initialized) return;
    await _client.connect();
    _initialized = true;
  }

  Stream<BleDiscoveredDevice> scan({
    Duration timeout = const Duration(seconds: 8),
  }) async* {
    await _initialize();
    final adapters = _client.adapters;
    if (adapters.isEmpty) throw StateError('BlueZ has no Bluetooth adapter');
    final adapter = adapters.first;
    final known = <String>{};
    try {
      await adapter.startDiscovery();
      final deadline = DateTime.now().add(timeout);
      // BlueZ can publish the Device1 object before its advertising UUIDs.
      // Poll the live cache for the fixed scan window so later property
      // updates are considered without extending the scan on each update.
      while (DateTime.now().isBefore(deadline)) {
        for (final device in _client.devices) {
          if (!device.uuids.any(
            (uuid) => uuid.toString().toLowerCase() == BleProtocol.serviceUuid,
          )) {
            continue;
          }
          final address = device.address;
          if (address.isEmpty || !known.add(address)) continue;
          yield BleDiscoveredDevice(
            id: address,
            name: device.name.isNotEmpty ? device.name : device.alias,
            rssi: device.rssi,
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    } finally {
      if (adapter.discovering) await adapter.stopDiscovery();
    }
  }

  @override
  Future<void> connect(String id) async {
    await _initialize();
    if (_device != null) throw StateError('A BLE device is already connected');
    final device = _client.devices
        .where((item) => item.address == id)
        .firstOrNull;
    if (device == null) {
      throw StateError('BlueZ device was not discovered: $id');
    }
    _device = device;
    _connectedByThisLink = false;
    _setState(BleLinkState.connecting);
    _deviceProperties = device.propertiesChanged.listen((properties) {
      if (!identical(_device, device)) return;
      if (!properties.contains('Connected')) return;
      if (device.connected) {
        _connectedByThisLink = true;
        _setState(BleLinkState.connected);
      } else {
        _setState(BleLinkState.disconnected);
      }
    });
    // Delegate passkey entry/confirmation to the system's registered BlueZ
    // agent. This client never accepts or prints a passkey itself.
    try {
      if (!device.paired) await device.pair();
      await device.connect();
      _connectedByThisLink = true;
      _setState(BleLinkState.connected);
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!device.servicesResolved && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (device.servicesResolved) return;
      await disconnect();
      throw TimeoutException('BlueZ GATT service discovery timed out');
    } catch (_) {
      await disconnect();
      rethrow;
    }
  }

  BlueZGattCharacteristic _characteristic(String uuid) {
    final device = _device;
    if (device == null || !device.connected) {
      throw StateError('BlueZ link is not connected');
    }
    for (final service in device.gattServices) {
      if (service.uuid.toString().toLowerCase() != BleProtocol.serviceUuid) {
        continue;
      }
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid.toString().toLowerCase() ==
            uuid.toLowerCase()) {
          return characteristic;
        }
      }
    }
    throw StateError('GATT characteristic not found: $uuid');
  }

  @override
  Future<List<int>> read(String uuid) => _characteristic(uuid).readValue();

  @override
  Future<void> write(String uuid, List<int> value) => _characteristic(
    uuid,
  ).writeValue(value, type: BlueZGattCharacteristicWriteType.request);

  @override
  Stream<List<int>> subscribe(String uuid) async* {
    final characteristic = _characteristic(uuid);
    final controller = StreamController<List<int>>();
    final valueSubscription = characteristic.propertiesChanged.listen((
      properties,
    ) {
      if (properties.contains('Value')) controller.add(characteristic.value);
    });
    try {
      await characteristic.startNotify();
      yield* controller.stream;
    } finally {
      await valueSubscription.cancel();
      await controller.close();
      await characteristic.stopNotify();
    }
  }

  @override
  Future<void> disconnect() async {
    final device = _device;
    _device = null;
    await _deviceProperties?.cancel();
    _deviceProperties = null;
    if (device != null && _connectedByThisLink && device.connected) {
      await device.disconnect();
    }
    _connectedByThisLink = false;
    _setState(BleLinkState.disconnected);
  }

  void _setState(BleLinkState state) {
    _currentState = state;
    if (!_state.isClosed) _state.add(state);
  }

  Future<void> dispose() async {
    await disconnect();
    if (_initialized) await _client.close();
    await _state.close();
  }
}
