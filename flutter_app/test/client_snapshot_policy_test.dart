import 'package:flutter_test/flutter_test.dart';
import 'package:satori_manager/runtime/client_snapshot_policy.dart';

void main() {
  bool accepts(Map data, {String? runtime = 'live'}) => acceptsTaskMessage(
    data,
    clientId: 'current',
    runtimeId: runtime,
    pendingOperations: {1: 'snapshot', 2: 'discover'},
    retiredRuntimes: {'retired'},
  );
  Map reply(int id, String runtime, {String type = 'accepted'}) => {
    'type': type,
    'id': id,
    'clientId': 'current',
    'snapshot': {'runtimeId': runtime, 'revision': 1000},
  };
  test('expired replies cannot refresh state or its freshness', () {
    expect(accepts(reply(3, 'live')), isFalse);
    expect(accepts(reply(3, 'live', type: 'rejected')), isFalse);
    expect(accepts(reply(3, 'old'), runtime: null), isFalse);
    expect(accepts(reply(2, 'live')), isTrue);
  });
  test('only live handshake may replace runtime; retired never returns', () {
    expect(accepts(reply(1, 'new')), isTrue);
    expect(accepts(reply(1, 'new'), runtime: null), isTrue);
    expect(accepts(reply(2, 'new')), isFalse);
    expect(accepts(reply(1, 'retired')), isFalse);
    expect(accepts({...reply(1, 'new'), 'clientId': 'old'}), isFalse);
  });
  test('broadcasts update synchronized runtime without claiming a new one', () {
    expect(
      accepts({
        'data': {'runtimeId': 'live'},
      }),
      isTrue,
    );
    expect(
      accepts({
        'data': {'runtimeId': 'old'},
      }),
      isFalse,
    );
    expect(
      accepts({
        'data': {'runtimeId': 'live'},
      }, runtime: null),
      isFalse,
    );
    expect(accepts({'type': 'error', 'message': 'safe error'}), isTrue);
  });
}
