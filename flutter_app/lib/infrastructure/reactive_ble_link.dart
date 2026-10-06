import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/ble_protocol.dart';
import '../core/device_session.dart';
import '../core/lan_window.dart';
import '../core/ota_window.dart';
import 'ble_discovery.dart';

/// Requests only the permissions needed by the current Android release.
/// Invoke from a foreground UI gesture before starting the connected-device
/// service. The UI must not create a BLE adapter or open a BLE connection.
Future<bool> requestBlePermissions() async {
  final sdkInt = await _androidSdkInt();
  final permissions = <Permission>[];
  if (sdkInt != null && sdkInt <= 30) {
    permissions.add(Permission.locationWhenInUse);
  } else {
    permissions
      ..add(Permission.bluetoothScan)
      ..add(Permission.bluetoothConnect);
  }
  final statuses = await permissions.request();
  return statuses.values.every(
    (status) => status.isGranted || status.isLimited,
  );
}

Future<int?> _androidSdkInt() async {
  try {
    final info = await DeviceInfoPlugin().androidInfo;
    return info.version.sdkInt;
  } on Exception {
    // If Android version cannot be queried, avoid adding a legacy location
    // permission. The BLE runtime will surface a permission failure on scan.
    return null;
  }
}

/// Android/iOS BLE transport. The runtime creates one instance and retains it
/// for the lifetime of the foreground-service FlutterEngine.
class ReactiveBleLink implements BleLink, BleLargeWriteLink {
  ReactiveBleLink({FlutterReactiveBle? ble})
    : ble = ble ?? FlutterReactiveBle();

  final FlutterReactiveBle ble;
  String? _deviceId;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  final StreamController<BleLinkState> _state =
      StreamController<BleLinkState>.broadcast();
  BleLinkState _currentState = BleLinkState.disconnected;
  bool _scanActive = false;
  int _connectionGeneration = 0;

  @override
  Stream<BleLinkState> get connectionState => _state.stream;

  BleLinkState get currentState => _currentState;

  /// Compatibility wrapper; prefer the top-level permission helper.
  static Future<bool> requestPermissions() => requestBlePermissions();

  /// Scans only for the SatoriEye service. Retain the same adapter/runtime
  /// instance for scanning and later connection ownership.
  Stream<BleDiscoveredDevice> scan({
    Duration timeout = const Duration(seconds: 8),
  }) {
    if (_scanActive) throw StateError('A BLE scan is already active');
    _scanActive = true;
    return Stream<BleDiscoveredDevice>.multi((controller) {
      Timer? timer;
      final subscription = ble
          .scanForDevices(
            withServices: [Uuid.parse(BleProtocol.serviceUuid)],
            scanMode: ScanMode.lowLatency,
            requireLocationServicesEnabled: false,
          )
          .listen(
            (device) => controller.add(
              BleDiscoveredDevice(
                id: device.id,
                name: device.name,
                rssi: device.rssi,
              ),
            ),
            onError: (Object error, StackTrace stack) {
              timer?.cancel();
              _scanActive = false;
              controller.addError(error, stack);
              controller.close();
            },
            onDone: () {
              timer?.cancel();
              _scanActive = false;
              controller.close();
            },
          );
      timer = Timer(timeout, () async {
        await subscription.cancel();
        _scanActive = false;
        await controller.close();
      });
      controller.onCancel = () async {
        timer?.cancel();
        _scanActive = false;
        await subscription.cancel();
      };
    });
  }

  @override
  Future<void> connect(String id) async {
    if (_connectionSubscription != null) {
      throw StateError('A BLE device is already connected or connecting');
    }
    _deviceId = id;
    _setState(BleLinkState.connecting);
    final generation = ++_connectionGeneration;
    final completer = Completer<void>();
    _connectionSubscription = ble
        .connectToDevice(
          id: id,
          servicesWithCharacteristicsToDiscover: {
            Uuid.parse(BleProtocol.serviceUuid): const [],
          },
          connectionTimeout: const Duration(seconds: 20),
        )
        .listen(
          (update) {
            if (generation != _connectionGeneration) return;
            switch (update.connectionState) {
              case DeviceConnectionState.connecting:
                _setState(BleLinkState.connecting);
              case DeviceConnectionState.connected:
                _setState(BleLinkState.connected);
                if (!completer.isCompleted) completer.complete();
              case DeviceConnectionState.disconnecting:
              case DeviceConnectionState.disconnected:
                _setState(BleLinkState.disconnected);
                if (!completer.isCompleted) {
                  completer.completeError(
                    StateError('BLE disconnected before becoming ready'),
                  );
                }
                _dropConnection(generation);
            }
          },
          onError: (Object error, StackTrace stack) {
            if (generation != _connectionGeneration) return;
            _setState(BleLinkState.disconnected);
            if (!completer.isCompleted) completer.completeError(error, stack);
            _dropConnection(generation);
          },
          onDone: () {
            if (generation != _connectionGeneration) return;
            _setState(BleLinkState.disconnected);
            if (!completer.isCompleted) {
              completer.completeError(StateError('BLE connection closed'));
            }
            _dropConnection(generation);
          },
        );
    try {
      await completer.future.timeout(const Duration(seconds: 25));
      if (Platform.isAndroid) {
        try {
          await ble
              .requestConnectionPriority(
                deviceId: id,
                priority: ConnectionPriority.highPerformance,
              )
              .timeout(const Duration(seconds: 2));
        } catch (_) {
          // This is a connection-parameter preference, not a prerequisite.
        }
      }
    } catch (_) {
      await disconnect();
      rethrow;
    }
  }

  @override
  Future<void> prepareLargeWrite(int length) async {
    final id = _deviceId;
    if (id == null || _currentState != BleLinkState.connected) {
      throw StateError('BLE link is not connected');
    }
    final mtu = await ble.requestMtu(deviceId: id, mtu: 256);
    if (mtu - 3 < length) {
      throw StateError('BLE MTU insufficient for Wi-Fi configuration');
    }
  }

  QualifiedCharacteristic _characteristic(String uuid) {
    final id = _deviceId;
    if (id == null || _currentState != BleLinkState.connected) {
      throw StateError('BLE link is not connected');
    }
    return QualifiedCharacteristic(
      deviceId: id,
      serviceId: Uuid.parse(BleProtocol.serviceUuid),
      characteristicId: Uuid.parse(uuid),
    );
  }

  @override
  Future<List<int>> read(String uuid) async {
    if (uuid == OtaWindowStatus.uuid || uuid == LanWindowStatus.lanUuid) {
      final id = _deviceId;
      if (id == null) throw StateError('BLE link is not connected');
      final services = await ble.getDiscoveredServices(id);
      final exists = services.any(
        (service) =>
            service.id.toString().toLowerCase() == BleProtocol.serviceUuid &&
            service.characteristics.any(
              (c) => c.id.toString().toLowerCase() == uuid.toLowerCase(),
            ),
      );
      if (!exists) throw const BleCharacteristicAbsent();
    }
    return ble.readCharacteristic(_characteristic(uuid));
  }

  @override
  Future<void> write(String uuid, List<int> value) =>
      ble.writeCharacteristicWithResponse(_characteristic(uuid), value: value);

  @override
  Stream<List<int>> subscribe(String uuid) => ble
      .subscribeToCharacteristic(_characteristic(uuid))
      .map((value) => List<int>.unmodifiable(value));

  @override
  Future<void> disconnect() async {
    ++_connectionGeneration;
    final subscription = _connectionSubscription;
    _connectionSubscription = null;
    _deviceId = null;
    await subscription?.cancel();
    _setState(BleLinkState.disconnected);
  }

  void _setState(BleLinkState state) {
    _currentState = state;
    if (!_state.isClosed) _state.add(state);
  }

  void _dropConnection(int generation) {
    if (generation != _connectionGeneration) return;
    final subscription = _connectionSubscription;
    _connectionSubscription = null;
    _deviceId = null;
    ++_connectionGeneration;
    if (subscription != null) unawaited(subscription.cancel());
  }

  Future<void> dispose() async {
    await disconnect();
    await _state.close();
  }
}
