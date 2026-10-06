import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:satori_manager/runtime/service_stop_policy.dart';

void main() {
  test('plugin failure value cannot be mistaken for confirmed stop', () async {
    await expectLater(
      stopServiceChecked(
        () async => ServiceRequestFailure(error: StateError('synthetic')),
      ),
      throwsStateError,
    );
    await stopServiceChecked(() async => const ServiceRequestSuccess());
  });
  test(
    'hung or thrown service stop fails within deadline; late success is ignored',
    () async {
      final pending = Completer<ServiceRequestResult>();
      await expectLater(
        stopServiceChecked(
          () => pending.future,
          timeout: const Duration(milliseconds: 1),
        ),
        throwsStateError,
      );
      pending.complete(const ServiceRequestSuccess());
      await expectLater(
        stopServiceChecked(() async => throw StateError('synthetic')),
        throwsStateError,
      );
    },
  );
}
