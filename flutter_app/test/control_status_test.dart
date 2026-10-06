import 'package:flutter_test/flutter_test.dart';
import 'package:satori_manager/core/control_status.dart';

void main() {
  test(
    'old, disconnected and future diagnostic samples cannot appear fresh',
    () {
      final now = DateTime.utc(2026, 10, 3, 1);
      Map sample(int seconds, {String connection = 'connected'}) => {
        'connection': connection,
        'diagnosticsAt': now
            .subtract(Duration(seconds: seconds))
            .toIso8601String(),
      };
      expect(diagnosticsAreFresh(sample(5), now: now), true);
      expect(diagnosticsAreFresh(sample(16), now: now), false);
      expect(diagnosticsAreFresh(sample(-1), now: now), false);
      expect(
        diagnosticsAreFresh(sample(5, connection: 'disconnected'), now: now),
        false,
      );
    },
  );
  test('ending status is explicit and cannot imply a powered-off device', () {
    expect(controlStatus({'endState': 'confirmed'}), '拍摄已结束，控制已释放');
    expect(controlStatus({'endState': 'unconfirmed'}), '拍摄已结束，设备停止未确认');
    expect(needsControlAttention({'endState': 'unconfirmed'}), true);
    expect(diagnosticStopReason(4), '控制心跳超时');
    expect(diagnosticFaults(3), '舵机输出驱动异常、配对存储异常');
  });
  test('notification and page status follow fields, not error wording', () {
    expect(
      controlStatus({
        'connection': 'connected',
        'controlPhase': 'configurationError',
        'error': 'arbitrary diagnostic',
      }),
      '设备配置异常，暂时无法控制',
    );
    expect(
      controlStatus({
        'connection': 'connected',
        'controlPhase': 'pauseUnconfirmed',
        'error': 'transport timeout',
      }),
      '暂停未确认',
    );
    expect(
      controlStatus({
        'connection': 'reconnecting',
        'controlPhase': 'paused',
        'error': 'auto-start restored',
      }),
      '正在重新连接…',
    );
    expect(
      controlStatus({'connection': 'connected', 'controlPhase': 'paused'}),
      '已暂停',
    );
  });
}
