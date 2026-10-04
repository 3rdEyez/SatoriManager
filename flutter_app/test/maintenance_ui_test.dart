import 'package:flutter_test/flutter_test.dart';
import 'package:satori_manager/main.dart';
import 'package:satori_manager/runtime/control_client.dart';

void main() {
  testWidgets('ending a shoot reminds user to switch physical power off', (
    tester,
  ) async {
    final client = ControlClient.preview({
      'connection': 'connected',
      'sessionPhase': 'readyPaused',
      'outputAuthorized': false,
      'discovered': <Object>[],
    });
    await tester.pumpWidget(SatoriApp(previewClient: client));
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('结束拍摄'));
    await tester.pump();
    expect(find.text('已结束控制。请关闭觉瞳实体电源；软件暂停不等于断电。'), findsOneWidget);
  });

  testWidgets(
    'unknown maintenance shows connection uncertainty, not unsupported firmware',
    (tester) async {
      final client = ControlClient.preview({
        'connection': 'connected',
        'sessionPhase': 'maintenance',
        'maintenancePath': 'unknown',
        'lanSupported': null,
        'otaSupported': null,
        'outputAuthorized': false,
        'discovered': <Object>[],
      });
      await tester.pumpWidget(SatoriApp(previewClient: client));
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('备用设备热点（手动选择）'), 250);
      expect(find.textContaining('局域网维护状态未确认'), findsOneWidget);
      expect(find.textContaining('备用热点维护状态未确认'), findsOneWidget);
      expect(find.textContaining('此设备固件不支持局域网'), findsNothing);
      expect(find.text('当前固件不支持无线升级窗口。'), findsNothing);
    },
  );
  testWidgets('confirmed missing capability remains unsupported', (
    tester,
  ) async {
    final client = ControlClient.preview({
      'connection': 'connected',
      'sessionPhase': 'readyPaused',
      'lanSupported': false,
      'otaSupported': false,
      'outputAuthorized': false,
      'discovered': <Object>[],
    });
    await tester.pumpWidget(SatoriApp(previewClient: client));
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('备用设备热点（手动选择）'), 250);
    expect(find.textContaining('此设备固件不支持局域网'), findsOneWidget);
    expect(find.text('当前固件不支持无线升级窗口。'), findsOneWidget);
    expect(find.textContaining('维护状态未确认'), findsNothing);
  });
}
