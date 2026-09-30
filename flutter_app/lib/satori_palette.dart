import 'package:flutter/material.dart';

/// App-owned surfaces and control colors for the two system brightness modes.
class SatoriPalette {
  const SatoriPalette({
    required this.background,
    required this.ink,
    required this.muted,
    required this.line,
    required this.purple,
    required this.button,
    required this.purpleSoft,
    required this.softBorder,
    required this.surface,
    required this.segment,
    required this.pink,
    required this.warningBackground,
    required this.dangerBackground,
    required this.success,
    required this.joystickSurface,
    required this.joystickBorder,
    required this.joystickLine,
    required this.knobStart,
    required this.knobEnd,
    required this.knobShadow,
    required this.sliderThumb,
  });

  final Color background;
  final Color ink;
  final Color muted;
  final Color line;
  final Color purple;
  final Color button;
  final Color purpleSoft;
  final Color softBorder;
  final Color surface;
  final Color segment;
  final Color pink;
  final Color warningBackground;
  final Color dangerBackground;
  final Color success;
  final Color joystickSurface;
  final Color joystickBorder;
  final Color joystickLine;
  final Color knobStart;
  final Color knobEnd;
  final Color knobShadow;
  final Color sliderThumb;

  static const light = SatoriPalette(
    background: Color(0xFFFCFBFF),
    ink: Color(0xFF15104C),
    muted: Color(0xFF8583A7),
    line: Color(0xFFE6E4F1),
    purple: Color(0xFF7957F2),
    button: Color(0xFF7957F2),
    purpleSoft: Color(0xFFF4F0FF),
    softBorder: Color(0xFFDDD5FF),
    surface: Color(0xFFF7F6FC),
    segment: Color(0xFFF4F3F9),
    pink: Color(0xFFFF3D83),
    warningBackground: Color(0xFFFFEEF5),
    dangerBackground: Color(0xFFFFF7FA),
    success: Color(0xFF2CC566),
    joystickSurface: Color(0xFFF7F6FC),
    joystickBorder: Color(0xFFD8D8E8),
    joystickLine: Color(0xFFD9D8E7),
    knobStart: Color(0xFFB6A2FF),
    knobEnd: Color(0xFF7052ED),
    knobShadow: Color(0x557963EB),
    sliderThumb: Colors.white,
  );

  static const dark = SatoriPalette(
    background: Color(0xFF171624),
    ink: Color(0xFFF6F3FF),
    muted: Color(0xFFB5B1CD),
    line: Color(0xFF3B3952),
    purple: Color(0xFFB49AFF),
    button: Color(0xFF7050D7),
    purpleSoft: Color(0xFF2B2543),
    softBorder: Color(0xFF5B4C82),
    surface: Color(0xFF242236),
    segment: Color(0xFF29263E),
    pink: Color(0xFFFF87B1),
    warningBackground: Color(0xFF3A2433),
    dangerBackground: Color(0xFF392431),
    success: Color(0xFF62D69B),
    joystickSurface: Color(0xFF242236),
    joystickBorder: Color(0xFF605B80),
    joystickLine: Color(0xFF4A4665),
    knobStart: Color(0xFFB6A2FF),
    knobEnd: Color(0xFF795CE6),
    knobShadow: Color(0x664D39A6),
    sliderThumb: Color(0xFFF6F3FF),
  );

  static SatoriPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}
