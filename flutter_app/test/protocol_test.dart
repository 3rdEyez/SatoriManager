import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:satori_manager/core/protocol.dart';

void main() {
  test('wire bytes and sentinel frame behavior', () {
    expect(Protocol.discovery, 'SatoriEye_DISCOVERY_REQUEST');
    expect(Protocol.heartbeat, 'SatoriEye_HEARTBEAT_REQUEST');
    expect(Protocol.pwm([1500, 1400, 1600]), 'CH1:1500CH2:1400CH3:1600');
    expect(
      Protocol.pwm([1500, 1400, 1600], smoothMs: 200),
      'SMOOTH:CH1:1500CH2:1400CH3:1600MS:200',
    );
    expect(Protocol.proportion(.4999), 1499);
    final frame = ActionFrame.fromJson({
      'CH1': -1,
      'CH2': -1,
      'CH3': 0,
      'duration': 200,
    });
    expect(frame.channels, [-1, -1, 0]);
    expect(frame.duration, const Duration(milliseconds: 200));
  });

  test('invalid battery remains unknown; invalid output fails', () {
    expect(
      Protocol.parse(utf8.encode('SatoriEye_DISCOVERY_RESPONSE'))?.battery,
      isNull,
    );
    expect(
      Protocol.parse(utf8.encode('SatoriEye_HEARTBEAT_RESPONSE,nan'))?.battery,
      isNull,
    );
    expect(
      Protocol.parse(utf8.encode('SatoriEye_HEARTBEAT_RESPONSE,101'))?.battery,
      isNull,
    );
    expect(
      Protocol.parse(
        utf8.encode('SatoriEye_DISCOVERY_RESPONSE,77,SIMULATOR'),
      )?.simulator,
      isTrue,
    );
    expect(
      Protocol.parse(utf8.encode('SatoriEye_DISCOVERY_RESPONSE,77,OTHER')),
      isNull,
    );
    expect(Protocol.parse([0xff]), isNull);
    expect(() => Protocol.proportion(double.nan), throwsFormatException);
    expect(() => Protocol.pwm([499, 1500, 1500]), throwsFormatException);
    expect(
      () => ActionFrame.fromJson({'CH1': -1, 'CH2': -1, 'CH3': 0}),
      throwsFormatException,
    );
  });

  test('bundled action compatibility', () {
    const json =
        '{"wink":[{"CH1":-1,"CH2":-1,"CH3":0.0,"duration":200},'
        '{"CH1":-1,"CH2":-1,"CH3":1,"duration":200}]}';
    final actions = parseActions(json);
    expect(actions['wink']?.length, 2);
    expect(actions['wink']?.last.channels.last, 1);
  });

  test('packaged action asset loads wink and wink2', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final actions = parseActions(
      await rootBundle.loadString('assets/actions/presets.json'),
    );
    expect(actions['wink']?.length, 2);
    expect(actions['wink2']?.length, 4);
  });

  test('user-confirmed ranges constrain every hardware channel', () {
    final profile = SafetyProfile([1450, 1400, 1300], [1550, 1600, 1700], [
      1500,
      1500,
      1500,
    ]);
    expect(profile.constrain([500, 2500, 500]), [1450, 1600, 1300]);
    expect(
      () => SafetyProfile([1500, 1500, 1500], [1400, 1600, 1600], [
        1500,
        1500,
        1500,
      ]),
      throwsFormatException,
    );
  });
}
