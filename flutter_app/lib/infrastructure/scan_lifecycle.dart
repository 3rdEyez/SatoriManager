import 'dart:async';

/// Owns one native scan. A timed-out cancellation never grants permission to
/// start another scan. Diagnostic fields deliberately contain no device data.
class ScanLifecycle<T> {
  ScanLifecycle({this.cancelTimeout = const Duration(seconds: 2)});

  final Duration cancelTimeout;
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  StreamSubscription<T>? _subscription;
  Timer? _deadline, _ticker;
  final Stopwatch _elapsed = Stopwatch();
  int _generation = 0, _count = 0;
  String _phase = 'idle';
  String? _reason, _requestedReason, _errorType;
  Future<void>? _cancellation;
  bool _disposed = false, _disposing = false;

  bool get canStart => stopConfirmed && !_disposed && !_disposing;
  bool get isScanning => _phase == 'scanning';
  bool get stopConfirmed =>
      const ['idle', 'stopped', 'failed'].contains(_phase);
  Map<String, Object?> diagnostics(String adapterStatus) => {
    'phase': _phase,
    'elapsedMs': _elapsed.elapsedMilliseconds,
    'resultCount': _count,
    'endReason': _reason,
    'errorType': _errorType,
    'adapterStatus': adapterStatus,
    'stopConfirmed': stopConfirmed,
    'canStart': canStart && !_disposed,
  };

  void _notify() {
    if (!_disposed) _changes.add(null);
  }

  void start(
    Stream<T> Function() source, {
    required void Function(T) onData,
    Duration timeout = const Duration(seconds: 8),
  }) {
    if (_disposed || !canStart) throw StateError('Scan stop is not confirmed');
    final generation = ++_generation;
    _phase = 'scanning';
    _reason = null;
    _requestedReason = null;
    _errorType = null;
    _count = 0;
    _subscription = null;
    _cancellation = null;
    _elapsed
      ..reset()
      ..start();
    _notify();
    try {
      _subscription = source().listen(
        (value) {
          if (generation != _generation || !isScanning || _disposed) return;
          _count++;
          onData(value);
          _notify();
        },
        onError: (Object _, StackTrace _) {
          if (generation != _generation || !isScanning) return;
          _phase = 'stopping';
          _errorType = 'sourceError';
          scheduleMicrotask(() {
            if (generation == _generation &&
                _phase == 'stopping' &&
                !_disposed) {
              unawaited(stop(reason: 'scanError'));
            }
          });
        },
        onDone: () {
          scheduleMicrotask(() {
            if (generation == _generation && isScanning && !_disposed) {
              _finish('done');
            }
          });
        },
      );
      if (isScanning) {
        _deadline = Timer(timeout, () => unawaited(stop(reason: 'timeout')));
        _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _notify());
      }
    } catch (_) {
      _errorType = 'sourceStartError';
      _finish('startError', failed: true);
      throw StateError('BLE scan could not start');
    }
  }

  void _finish(String reason, {bool failed = false}) {
    _deadline?.cancel();
    _ticker?.cancel();
    _elapsed.stop();
    _phase = failed ? 'failed' : 'stopped';
    _reason = reason;
    _subscription = null;
    _notify();
  }

  Future<bool> stop({String reason = 'cancelled'}) async {
    if (stopConfirmed) return true;
    final generation = _generation;
    _deadline?.cancel();
    _ticker?.cancel();
    _phase = 'stopping'; // Fence late data before awaiting native cancellation.
    _requestedReason ??= reason;
    _reason = _requestedReason;
    _notify();
    _cancellation ??=
        Future<void>.sync(() async {
          await _subscription?.cancel();
        }).then(
          (_) {
            if (generation == _generation) {
              final end = _requestedReason ?? reason;
              _errorType = end == 'scanError' ? 'sourceError' : null;
              _finish(end, failed: end == 'scanError');
            }
          },
          onError: (Object _, StackTrace _) {
            if (generation == _generation) {
              _phase = 'stopUnknown';
              _reason = 'cancelError';
              _errorType = 'cancelError';
              _elapsed.stop();
              _notify();
            }
            throw StateError('BLE scan stop is not confirmed');
          },
        );
    try {
      await _cancellation!.timeout(cancelTimeout);
      return stopConfirmed;
    } catch (_) {
      if (generation == _generation && !stopConfirmed) {
        _phase = 'stopUnknown';
        if (_reason != 'cancelError') {
          _reason = 'cancelTimeout';
          _errorType = 'cancelTimeout';
        }
        _elapsed.stop();
        _notify();
      }
      return false;
    }
  }

  Future<void> dispose() async {
    _disposing = true;
    await stop(reason: 'destroyed');
    _disposed = true;
    _deadline?.cancel();
    _ticker?.cancel();
    await _changes.close();
  }
}
