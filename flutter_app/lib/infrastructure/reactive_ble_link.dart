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
import 'scan_lifecycle.dart';

/// Requests only the permissions needed by the current Android release.
/// Invoke from a foreground UI gesture before starting the connected-device
/// service. The UI must not create a BLE adapter or open a BLE connection.
Map<String, Object?> blePermissionDiagnostics = {
  'sdkInt': null,
  'locationPermission': 'notRequested',
  'bluetoothScan': 'notRequested',
  'bluetoothConnect': 'notRequested',
  'phase': 'notRequested',
};

Future<bool> requestBlePermissions() async {
  blePermissionDiagnostics = {
    'sdkInt': null,
    'locationPermission': 'notRequested',
    'bluetoothScan': 'notRequested',
    'bluetoothConnect': 'notRequested',
    'phase': 'checkingSdk',
  };
  try {
    final sdkInt = await _androidSdkInt().timeout(const Duration(seconds: 5));
    blePermissionDiagnostics['sdkInt'] = sdkInt;
    final permissions = <Permission>[];
    if (sdkInt != null && sdkInt <= 30) {
      permissions.add(Permission.locationWhenInUse);
    } else {
      permissions
        ..add(Permission.bluetoothScan)
        ..add(Permission.bluetoothConnect);
    }
    blePermissionDiagnostics['phase'] = 'requestingPermissions';
    final statuses = await permissions.request().timeout(
      const Duration(seconds: 15),
    );
    for (final entry in statuses.entries) {
      final field = entry.key == Permission.locationWhenInUse
          ? 'locationPermission'
          : entry.key == Permission.bluetoothScan
          ? 'bluetoothScan'
          : 'bluetoothConnect';
      blePermissionDiagnostics[field] = entry.value.name;
    }
    blePermissionDiagnostics['phase'] = 'completed';
    return statuses.values.every(
      (status) => status.isGranted || status.isLimited,
    );
  } on TimeoutException {
    blePermissionDiagnostics['phase'] = 'timeout';
    throw StateError('蓝牙权限确认超时，请查看系统权限状态后重试');
  } catch (_) {
    blePermissionDiagnostics['phase'] = 'failed';
    throw StateError('蓝牙权限确认失败，请查看系统权限状态');
  }
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
  final _scan = ScanLifecycle<BleDiscoveredDevice>();
  int _connectionGeneration = 0;

  @override
  Stream<BleLinkState> get connectionState => _state.stream;

  BleLinkState get currentState => _currentState;

  /// Compatibility wrapper; prefer the top-level permission helper.
  static Future<bool> requestPermissions() => requestBlePermissions();

  Stream<void> get scanChanges => _scan.changes;
  Map<String, Object?> get scanDiagnostics =>
      _scan.diagnostics(ble.status.name);
  bool get isScanning => _scan.isScanning;

  /// One service-owned scan, with no overlapping native start after an
  /// unconfirmed stop. Native exception messages never enter diagnostics.
  void startScan({
    required void Function(BleDiscoveredDevice) onDevice,
    Duration timeout = const Duration(seconds: 8),
  }) => _scan.start(
    () => ble
        .scanForDevices(
          withServices: [Uuid.parse(BleProtocol.serviceUuid)],
          scanMode: ScanMode.lowLatency,
          requireLocationServicesEnabled: false,
        )
        .map(
          (device) => BleDiscoveredDevice(
            id: device.id,
            name: device.name,
            rssi: device.rssi,
          ),
        ),
    onData: onDevice,
    timeout: timeout,
  );

  Future<bool> stopScan({String reason = 'cancelled'}) =>
      _scan.stop(reason: reason);

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
    await _scan.dispose();
    await disconnect();
    await _state.close();
  }
}
