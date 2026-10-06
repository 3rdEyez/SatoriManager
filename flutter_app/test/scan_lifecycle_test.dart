import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:satori_manager/infrastructure/scan_lifecycle.dart';

class TestSource extends Stream<int> {
  TestSource({Future<void> Function()? cancel})
    : subscription = TestSubscription(cancel ?? (() async {}));
  final TestSubscription subscription;
  void Function(int)? data;
  Function? error;
  void Function()? done;
  @override
  StreamSubscription<int> listen(
    void Function(int)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    data = onData;
    error = onError;
    done = onDone;
    return subscription;
  }

  void fail() => Function.apply(error!, [
    StateError('synthetic-secret'),
    StackTrace.current,
  ]);
}

class TestSubscription implements StreamSubscription<int> {
  TestSubscription(this.cancelAction);
  final Future<void> Function() cancelAction;
  int cancellations = 0;
  @override
  Future<void> cancel() {
    cancellations++;
    return cancelAction();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 5));
void main() {
  test('synchronous source throw is failed and safely retryable', () async {
    final scan = ScanLifecycle<int>();
    expect(
      () => scan.start(
        () => throw StateError('synthetic-secret'),
        onData: (_) {},
      ),
      throwsStateError,
    );
    expect(scan.diagnostics('ready')['phase'], 'failed');
    expect(scan.diagnostics('ready')['endReason'], 'startError');
    expect(
      scan.diagnostics('ready').toString(),
      isNot(contains('synthetic-secret')),
    );
    scan.start(() => TestSource(), onData: (_) {});
    expect(await scan.stop(), true);
    await scan.dispose();
  });
  test('timeout confirms native cancel before allowing retry', () async {
    final source = TestSource();
    final scan = ScanLifecycle<int>();
    scan.start(
      () => source,
      onData: (_) {},
      timeout: const Duration(milliseconds: 5),
    );
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(source.subscription.cancellations, 1);
    expect(scan.diagnostics('ready')['endReason'], 'timeout');
    expect(scan.stopConfirmed, true);
    await scan.dispose();
  });
  test('async error cancels source and sanitizes diagnostic details', () async {
    final source = TestSource();
    final scan = ScanLifecycle<int>();
    scan.start(() => source, onData: (_) {});
    source.fail();
    await settle();
    expect(source.subscription.cancellations, 1);
    expect(scan.diagnostics('ready')['phase'], 'failed');
    expect(scan.diagnostics('ready')['endReason'], 'scanError');
    expect(
      scan.diagnostics('ready').toString(),
      isNot(contains('synthetic-secret')),
    );
    await scan.dispose();
  });
  test(
    'native done confirms completion and old callbacks cannot touch retry',
    () async {
      final old = TestSource();
      final scan = ScanLifecycle<int>();
      final values = <int>[];
      scan.start(() => old, onData: values.add);
      old.data!(1);
      old.done!();
      await settle();
      expect(scan.diagnostics('ready')['endReason'], 'done');
      final current = TestSource();
      scan.start(() => current, onData: values.add);
      old.data!(2);
      old.fail();
      old.done!();
      current.data!(3);
      await settle();
      expect(values, [1, 3]);
      expect(scan.isScanning, true);
      expect(scan.diagnostics('ready')['resultCount'], 1);
      await scan.dispose();
    },
  );
  test('cancel hangs locks overlap; late success can confirm stop', () async {
    final gate = Completer<void>();
    final source = TestSource(cancel: () => gate.future);
    final scan = ScanLifecycle<int>(
      cancelTimeout: const Duration(milliseconds: 5),
    );
    final values = <int>[];
    scan.start(() => source, onData: values.add);
    final stopping = scan.stop();
    source.data!(42);
    expect(await stopping, false);
    expect(scan.diagnostics('ready')['phase'], 'stopUnknown');
    expect(scan.diagnostics('ready')['endReason'], 'cancelTimeout');
    expect(
      () => scan.start(() => TestSource(), onData: values.add),
      throwsStateError,
    );
    expect(values, isEmpty);
    gate.complete();
    await settle();
    expect(scan.stopConfirmed, true);
    expect(scan.canStart, true);
    expect(scan.diagnostics('ready')['endReason'], 'cancelled');
    await scan.dispose();
  });
  test('cancel throw remains unknown and never permits overlap', () async {
    final source = TestSource(
      cancel: () async => throw StateError('synthetic-secret'),
    );
    final scan = ScanLifecycle<int>();
    scan.start(() => source, onData: (_) {});
    expect(await scan.stop(), false);
    expect(scan.diagnostics('ready')['endReason'], 'cancelError');
    expect(scan.canStart, false);
    expect(
      scan.diagnostics('ready').toString(),
      isNot(contains('synthetic-secret')),
    );
    expect(
      () => scan.start(() => TestSource(), onData: (_) {}),
      throwsStateError,
    );
    await scan.dispose();
  });
  test('concurrent stop uses one native cancellation', () async {
    final gate = Completer<void>();
    final source = TestSource(cancel: () => gate.future);
    final scan = ScanLifecycle<int>();
    scan.start(() => source, onData: (_) {});
    final a = scan.stop();
    final b = scan.stop();
    gate.complete();
    expect(await a, true);
    expect(await b, true);
    expect(source.subscription.cancellations, 1);
    await scan.dispose();
  });
  test(
    'dispose fences a start immediately and ignores late source events',
    () async {
      final gate = Completer<void>();
      final source = TestSource(cancel: () => gate.future);
      final scan = ScanLifecycle<int>(
        cancelTimeout: const Duration(milliseconds: 5),
      );
      final values = <int>[];
      scan.start(() => source, onData: values.add);
      final disposing = scan.dispose();
      expect(
        () => scan.start(() => TestSource(), onData: values.add),
        throwsStateError,
      );
      await disposing;
      source.data!(42);
      gate.complete();
      await settle();
      expect(values, isEmpty);
      expect(scan.canStart, false);
    },
  );
}
