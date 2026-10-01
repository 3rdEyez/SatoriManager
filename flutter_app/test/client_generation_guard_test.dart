import 'package:flutter_test/flutter_test.dart';
import 'package:satori_manager/runtime/client_generation_guard.dart';

void main() {
  group('ClientGenerationGuard', () {
    test('snapshot handshakes admit commands for the exact runtime', () {
      final guard = ClientGenerationGuard();
      expect(
        guard.authorize({
          'clientId': 'ui-a',
          'op': 'snapshot',
        }, runtimeId: 'r1'),
        isNull,
      );
      expect(
        guard.authorize({
          'clientId': 'ui-a',
          'op': 'manual',
          'expectedRuntimeId': 'r1',
        }, runtimeId: 'r1'),
        isNull,
      );
    });

    test('commands require a handshake, client id, and current runtime', () {
      final guard = ClientGenerationGuard();
      expect(
        guard.authorize({
          'clientId': 'ui-a',
          'op': 'stop',
          'expectedRuntimeId': 'r1',
        }, runtimeId: 'r1'),
        isNotNull,
      );
      guard.authorize({'clientId': 'ui-a', 'op': 'snapshot'}, runtimeId: 'r1');
      expect(
        guard.authorize({
          'clientId': 'ui-a',
          'op': 'stop',
          'expectedRuntimeId': 'old-runtime',
        }, runtimeId: 'r1'),
        isNotNull,
      );
      expect(
        guard.authorize({
          'op': 'stop',
          'expectedRuntimeId': 'r1',
        }, runtimeId: 'r1'),
        isNotNull,
      );
    });

    test(
      'new snapshot transfers ownership and retired client cannot reclaim it',
      () {
        final guard = ClientGenerationGuard();
        expect(
          guard.authorize({
            'clientId': 'ui-a',
            'op': 'snapshot',
          }, runtimeId: 'r1'),
          isNull,
        );
        expect(
          guard.authorize({
            'clientId': 'ui-b',
            'op': 'snapshot',
          }, runtimeId: 'r1'),
          isNull,
        );
        expect(guard.activeClientId, 'ui-b');
        expect(guard.retiredClientIds, contains('ui-a'));
        expect(
          guard.authorize({
            'clientId': 'ui-a',
            'op': 'snapshot',
          }, runtimeId: 'r1'),
          isNotNull,
        );
        expect(guard.activeClientId, 'ui-b');
        expect(
          guard.authorize({
            'clientId': 'ui-a',
            'op': 'manual',
            'expectedRuntimeId': 'r1',
          }, runtimeId: 'r1'),
          isNotNull,
        );
        expect(
          guard.authorize({
            'clientId': 'ui-b',
            'op': 'stop',
            'expectedRuntimeId': 'r1',
          }, runtimeId: 'r1'),
          isNull,
        );
      },
    );

    test('snapshot handshake does not change service runtime identity', () {
      const runtimeId = 'service-runtime';
      final guard = ClientGenerationGuard();
      guard.authorize({
        'clientId': 'ui-a',
        'op': 'snapshot',
      }, runtimeId: runtimeId);
      guard.authorize({
        'clientId': 'ui-b',
        'op': 'snapshot',
      }, runtimeId: runtimeId);
      expect(
        guard.authorize({
          'clientId': 'ui-b',
          'op': 'manual',
          'expectedRuntimeId': runtimeId,
        }, runtimeId: runtimeId),
        isNull,
      );
    });
  });
}
