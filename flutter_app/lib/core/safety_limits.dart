/// User-confirmed logical input limits, never inferred from a sample posture.
class SafetyLimits {
  /// Default logical range retained from the original Qt Satori C3 controls.
  /// This is not a measured mechanical safe envelope; firmware calibration and
  /// per-channel clamping remain responsible for physical travel limits.
  static final SafetyLimits builtInSatoriC3 = SafetyLimits(
    [500, 500, 500],
    [2500, 2500, 2500],
  );

  SafetyLimits(List<int> minimum, List<int> maximum)
    : minimum = List.unmodifiable(minimum),
      maximum = List.unmodifiable(maximum) {
    if (minimum.length != 3 || maximum.length != 3) {
      throw const FormatException('需要三通道安全范围');
    }
    for (var i = 0; i < 3; i++) {
      if (minimum[i] < 500 || maximum[i] > 2500 || minimum[i] > maximum[i]) {
        throw const FormatException('安全范围必须位于 500–2500 逻辑值内');
      }
    }
  }
  final List<int> minimum;
  final List<int> maximum;
  List<int> constrain(List<int> values) => [
    for (var i = 0; i < 3; i++) values[i].clamp(minimum[i], maximum[i]),
  ];
  bool contains(List<int> values) =>
      values.length == 3 &&
      List.generate(
        3,
        (i) => values[i] >= minimum[i] && values[i] <= maximum[i],
      ).every((v) => v);
  Map<String, Object> toJson() => {'minimum': minimum, 'maximum': maximum};
  factory SafetyLimits.fromJson(Map value) => SafetyLimits(
    List<int>.from(value['minimum'] as List),
    List<int>.from(value['maximum'] as List),
  );
}
