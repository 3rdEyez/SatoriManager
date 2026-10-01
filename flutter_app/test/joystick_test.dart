import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:satori_manager/joystick_pad.dart';

void main() {
  test('joystick maps and clamps the original CH1/CH2 directions', () {
    const size = Size.square(200);
    expect(
      JoystickPad.positionFor(const Offset(100, 100), size),
      const Offset(.5, .5),
    );
    expect(
      JoystickPad.positionFor(const Offset(-100, 100), size),
      const Offset(0, .5),
    );
    expect(
      JoystickPad.positionFor(const Offset(100, 300), size),
      const Offset(.5, 1),
    );
    final diagonal = JoystickPad.positionFor(const Offset(200, 200), size);
    expect(diagonal.dx, closeTo(.85355, .0001));
    expect(diagonal.dy, closeTo(.85355, .0001));
  });

  testWidgets('drag emits direction updates and release', (tester) async {
    final positions = <Offset>[];
    var released = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 232,
              child: JoystickPad(
                x: .5,
                y: .5,
                onChanged: (x, y) => positions.add(Offset(x, y)),
                onReleased: () => released++,
              ),
            ),
          ),
        ),
      ),
    );
    final center = tester.getCenter(find.byType(JoystickPad));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(116, 0));
    await gesture.up();
    expect(positions.last.dx, closeTo(1, .001));
    expect(positions.last.dy, closeTo(.5, .001));
    expect(released, 1);
  });
}
