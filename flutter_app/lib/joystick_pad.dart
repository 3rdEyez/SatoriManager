import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'satori_palette.dart';

/// CH1 runs left to right, and CH2 runs top to bottom.
class JoystickPad extends StatelessWidget {
  const JoystickPad({
    super.key,
    required this.x,
    required this.y,
    required this.onChanged,
    required this.onReleased,
  });

  final double x;
  final double y;
  final void Function(double x, double y) onChanged;
  final VoidCallback onReleased;

  static Offset positionFor(Offset local, Size size) {
    final radius = math.min(size.width, size.height) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    if (radius <= 0) return const Offset(.5, .5);
    final delta = local - center;
    final distance = delta.distance;
    final clamped = distance > radius ? delta * (radius / distance) : delta;
    return Offset((clamped.dx / radius + 1) / 2, (clamped.dy / radius + 1) / 2);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final palette = SatoriPalette.of(context);
      final diameter = math.min(constraints.maxWidth, 232.0);
      final size = Size.square(diameter);
      void update(Offset local) {
        final position = positionFor(local, size);
        onChanged(position.dx, position.dy);
      }

      return Center(
        child: SizedBox.square(
          dimension: diameter,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (details) => update(details.localPosition),
            onPanUpdate: (details) => update(details.localPosition),
            onPanEnd: (_) => onReleased(),
            onPanCancel: onReleased,
            child: Semantics(
              label: '方向摇杆，左右控制 CH1，上下控制 CH2',
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: palette.joystickSurface,
                      border: Border.all(
                        color: palette.joystickBorder,
                        width: 1.5,
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: diameter - 12,
                    color: palette.joystickLine,
                  ),
                  Container(
                    width: diameter - 12,
                    height: 1,
                    color: palette.joystickLine,
                  ),
                  Positioned(
                    left: (diameter - 48) * x.clamp(0.0, 1.0),
                    top: (diameter - 48) * y.clamp(0.0, 1.0),
                    child: IgnorePointer(
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [palette.knobStart, palette.knobEnd],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: palette.knobShadow,
                              blurRadius: 15,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
