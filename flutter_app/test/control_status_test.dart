import 'package:flutter_test/flutter_test.dart';
import 'package:satori_manager/core/control_status.dart';

void main() {
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
