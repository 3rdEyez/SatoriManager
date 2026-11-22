import 'dart:async';
import '../core/ble_protocol.dart';

/// UUIDs only: no device addresses, values, credentials or native error text.
class GattDiscovery {
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  int _generation = 0;
  String _phase = 'idle';
  String? _failure;
  DateTime? _completedAt;
  Map<String, List<String>> _services = {};
  Map<String, Object?> _native = {};

  bool get isReady => _phase == 'completed';

  bool? contains(String uuid) => _phase != 'completed'
      ? null
      : _services[BleProtocol.serviceUuid]?.contains(uuid.toLowerCase());

  Map<String, Object?> get diagnostics => {
    'phase': _phase,
    'failure': _failure,
    'completedAt': _completedAt?.toIso8601String(),
    'source': 'explicitDiscovery',
    'native': Map<String, Object?>.of(_native),
    'services': _services.entries
        .map(
          (e) => {'uuid': e.key, 'characteristics': List<String>.of(e.value)},
        )
        .toList(),
    for (final suffix in ['0006', '0007', '0008'])
      suffix: contains('4d89f6a0-73b9-4f14-9d3e-63b2145a$suffix'),
  };

  void reset() {
    ++_generation;
    _phase = 'idle';
    _failure = null;
    _completedAt = null;
    _services = {};
    _native = {};
    _emit();
  }

  Future<void> discover(
    Future<Map<String, List<String>>> Function() query, {
    Duration timeout = const Duration(seconds: 8),
    Future<Map<String, Object?>> Function()? nativeEvidence,
  }) async {
    final generation = ++_generation;
    _phase = 'discovering';
    _failure = null;
    _completedAt = null;
    _services = {};
    _native = {};
    _emit();
    try {
      final services = await query().timeout(timeout);
      if (generation != _generation) return;
      _services = {
        for (final entry in services.entries)
          entry.key.toLowerCase():
              entry.value.map((v) => v.toLowerCase()).toList()..sort(),
      };
      _phase = _services.containsKey(BleProtocol.serviceUuid)
          ? 'completed'
          : 'missingService';
      _completedAt = DateTime.now();
    } on TimeoutException {
      if (generation != _generation) return;
      _phase = 'failed';
      _failure = 'timeout';
    } catch (_) {
      if (generation != _generation) return;
      _phase = 'failed';
      _failure = 'nativeDiscoveryFailed';
    }
    if (generation == _generation && nativeEvidence != null) {
      try {
        final evidence = await nativeEvidence().timeout(
          const Duration(seconds: 1),
        );
        if (generation == _generation) {
          const fields = [
            'operation',
            'source',
            'phase',
            'startedAtMs',
            'completedAtMs',
            'callbackReceived',
            'accepted',
            'status',
            'failure',
          ];
          _native = {
            for (final field in fields)
              if (evidence.containsKey(field)) field: evidence[field],
          };
        }
      } catch (_) {
        /* Native evidence is optional; no raw error text. */
      }
    }
    if (generation == _generation) _emit();
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> dispose() async {
    reset();
    await _changes.close();
  }
}
