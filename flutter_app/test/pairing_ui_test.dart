import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:satori_manager/main.dart';
import 'package:satori_manager/runtime/control_client.dart';

class PairingPreviewClient extends ControlClient {
  PairingPreviewClient({bool connected = true, bool shared = true})
    : super.preview({
        'connection': connected ? 'connected' : 'disconnected',
        'supportsOwnerManagement': true,
        'supportsSharedPairing': shared,
        'outputAuthorized': false,
        'identity': 'synthetic',
        'sessionPhase': 'readyPaused',
        'discovered': <Object>[],
      });
  final sent = <(String, Map<String, Object?>)>[];
  @override
  Future<void> send(String op, [Map<String, Object?> args = const {}]) async {
    sent.add((op, args));
  }
}

Future<void> devicePage(
  WidgetTester tester,
  PairingPreviewClient client,
) async {
  await tester.pumpWidget(SatoriApp(previewClient: client));
  await tester.tap(find.text('设置'));
  await tester.pumpAndSettle();
}

Future<void> scrollToAction(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(find.text(label), 250);
  await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('first pairing explains default and keeps existing codes', (
    tester,
  ) async {
    final client = PairingPreviewClient(connected: false);
    await devicePage(tester, client);
    await tester.tap(find.text('配对帮助'));
    await tester.pumpAndSettle();
    expect(find.textContaining('新设备默认配对码：123456'), findsOneWidget);
    expect(find.textContaining('修改过请使用新码'), findsOneWidget);
    expect(client.sent, isEmpty);
  });

  testWidgets(
    'code dialog masks input and rejects default/mismatch before sending',
    (tester) async {
      final client = PairingPreviewClient();
      await devicePage(tester, client);
      await scrollToAction(tester, '修改配对码');
      await tester.tap(find.text('修改配对码'));
      await tester.pumpAndSettle();
      final inputs = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      expect(inputs, findsNWidgets(2));
      for (final field in tester.widgetList<TextField>(inputs)) {
        expect(field.obscureText, isTrue);
        expect(field.enableSuggestions, isFalse);
      }
      await tester.enterText(inputs.at(0), '123456');
      await tester.enterText(inputs.at(1), '123456');
      await tester.tap(find.text('暂停并保存'));
      await tester.pumpAndSettle();
      expect(find.text('不能使用默认码123456'), findsOneWidget);
      expect(client.sent, isEmpty);
      await tester.enterText(inputs.at(0), '006789');
      await tester.enterText(inputs.at(1), '006780');
      await tester.tap(find.text('暂停并保存'));
      await tester.pumpAndSettle();
      expect(find.text('两次输入不一致'), findsOneWidget);
      expect(client.sent, isEmpty);
      await tester.enterText(inputs.at(1), '006789');
      await tester.tap(find.text('暂停并保存'));
      await tester.pumpAndSettle();
      expect(client.sent.single.$1, 'setPairingCode');
      expect(client.sent.single.$2['code'], '006789');
      expect(find.textContaining('006789'), findsNothing);
    },
  );

  testWidgets('changing phone requires separate confirmation', (tester) async {
    final client = PairingPreviewClient(shared: false);
    await devicePage(tester, client);
    await scrollToAction(tester, '更换手机');
    await tester.tap(find.text('更换手机'));
    await tester.pumpAndSettle();
    expect(find.text('更换主控手机'), findsOneWidget);
    expect(client.sent, isEmpty);
    await tester.tap(find.text('开启60秒换绑'));
    await tester.pumpAndSettle();
    expect(client.sent.single.$1, 'openTransfer');
  });
  testWidgets('shared pairing explains exclusive use and hides transfer', (
    tester,
  ) async {
    final client = PairingPreviewClient();
    await devicePage(tester, client);
    await scrollToAction(tester, '修改配对码');
    expect(find.textContaining('同一时间只能连接 1 台'), findsOneWidget);
    expect(find.textContaining('最多保存 8 台手机'), findsOneWidget);
    expect(find.text('更换手机'), findsNothing);
    expect(find.text('取消换绑窗口'), findsNothing);
    expect(client.sent, isEmpty);
  });
  testWidgets('firmware limits have no editable UI', (tester) async {
    final client = PairingPreviewClient(connected: false);
    await devicePage(tester, client);
    expect(find.text('连接方式'), findsOneWidget);
    expect(find.text('蓝牙 · BLE'), findsOneWidget);
    expect(find.textContaining('安全范围'), findsNothing);
    expect(find.text('高级维护'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });
}
