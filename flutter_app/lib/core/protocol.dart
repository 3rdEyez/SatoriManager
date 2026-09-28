import 'dart:convert';

class Endpoint {
  const Endpoint(this.host, this.port);
  final String host;
  final int port;
  Map<String, Object> toJson() => {'host': host, 'port': port};
  @override
  bool operator ==(Object other) =>
      other is Endpoint && host == other.host && port == other.port;
  @override
  int get hashCode => Object.hash(host, port);
  @override
  String toString() => '$host:$port';
}

enum ReplyKind { discovery, heartbeat, mode }

class Reply {
  const Reply(this.kind, {this.battery, this.mode, this.simulator = false});
  final ReplyKind kind;
  final int? battery;
  final String? mode;
  final bool simulator;
}

class Protocol {
  static const discovery = 'SatoriEye_DISCOVERY_REQUEST';
  static const heartbeat = 'SatoriEye_HEARTBEAT_REQUEST';
  static const disconnect = 'SatoriEye_DISCONNECT';

  static Reply? parse(List<int> bytes) {
    final String message;
    try {
      message = utf8.decode(bytes);
    } on FormatException {
      return null;
    }
    final parts = message.split(',');
    final kind = switch (parts.first) {
      'SatoriEye_DISCOVERY_RESPONSE' => ReplyKind.discovery,
      'SatoriEye_HEARTBEAT_RESPONSE' => ReplyKind.heartbeat,
      _ => null,
    };
    final simulator =
        kind == ReplyKind.discovery &&
        parts.length == 3 &&
        parts[2] == 'SIMULATOR';
    if (kind != null && (parts.length <= 2 || simulator)) {
      final value = parts.length >= 2 ? int.tryParse(parts[1]) : null;
      return Reply(
        kind,
        battery: value != null && value >= 0 && value <= 100 ? value : null,
        simulator: simulator,
      );
    }
    if (message == 'SET_MODE_SUCCESS:Sleep') {
      return const Reply(ReplyKind.mode, mode: 'Sleep');
    }
    return null;
  }

  static int proportion(num value) {
    if (!value.isFinite || value < 0 || value > 1) {
      throw const FormatException('通道比例必须在 0–1 之间');
    }
    return (500 + 2000 * value).truncate();
  }

  static String pwm(List<int> channels, {int? smoothMs}) {
    if (channels.length != 3 || channels.any((v) => v < 500 || v > 2500)) {
      throw const FormatException('PWM 必须在 500–2500 之间');
    }
    if (smoothMs != null && (smoothMs <= 0 || smoothMs > 60000)) {
      throw const FormatException('无效平滑时长');
    }
    final body = 'CH1:${channels[0]}CH2:${channels[1]}CH3:${channels[2]}';
    return smoothMs == null ? body : 'SMOOTH:${body}MS:$smoothMs';
  }
}

class ActionFrame {
  ActionFrame(this.channels, this.duration);
  final List<num> channels;
  final Duration duration;

  factory ActionFrame.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('动作帧必须是对象');
    final channels = <num>[];
    for (final key in ['CH1', 'CH2', 'CH3']) {
      final v = value[key];
      if (v is! num || !v.isFinite || (v != -1 && (v < 0 || v > 1))) {
        throw FormatException('无效动作通道 $key');
      }
      channels.add(v);
    }
    final ms = value['duration'];
    if (ms is! int || ms <= 0 || ms > 60000) {
      throw const FormatException('动作时长必须为 1–60000 毫秒整数');
    }
    return ActionFrame(channels, Duration(milliseconds: ms));
  }
}

Map<String, List<ActionFrame>> parseActions(String json) {
  final value = jsonDecode(json);
  if (value is! Map<String, dynamic>) {
    throw const FormatException('动作资源必须是对象');
  }
  return value.map((name, frames) {
    if (frames is! List || frames.isEmpty) {
      throw FormatException('动作 $name 没有有效帧');
    }
    return MapEntry(name, frames.map(ActionFrame.fromJson).toList());
  });
}

class SafetyProfile {
  SafetyProfile(this.minimum, this.maximum, this.initial) {
    if ([minimum, maximum, initial].any((v) => v.length != 3)) {
      throw const FormatException('必须设置三个通道');
    }
    for (var i = 0; i < 3; i++) {
      if (minimum[i] < 500 ||
          maximum[i] > 2500 ||
          minimum[i] > maximum[i] ||
          initial[i] < minimum[i] ||
          initial[i] > maximum[i]) {
        throw const FormatException('初始目标须位于已确认范围内，协议范围为 500–2500');
      }
    }
  }
  final List<int> minimum;
  final List<int> maximum;
  final List<int> initial;
  List<int> constrain(List<int> target) => [
    for (var i = 0; i < 3; i++) target[i].clamp(minimum[i], maximum[i]),
  ];
  Map<String, Object> toJson() => {
    'minimum': minimum,
    'maximum': maximum,
    'initial': initial,
  };
  factory SafetyProfile.fromJson(Map value) => SafetyProfile(
    List<int>.from(value['minimum'] as List),
    List<int>.from(value['maximum'] as List),
    List<int>.from(value['initial'] as List),
  );
  factory SafetyProfile.simulator() =>
      SafetyProfile([500, 500, 500], [2500, 2500, 2500], [1500, 1500, 1500]);
}
