import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'core/protocol.dart';
import 'joystick_pad.dart';
import 'runtime/control_client.dart';

const _background = Color(0xFF0B1020);
const _surface = Color(0xFF171D30);
const _surfaceRaised = Color(0xFF202840);
const _accent = Color(0xFFB6A2FF);
const _mint = Color(0xFF80DFC0);
const _muted = Color(0xFFAAB4CE);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'satori_control',
      channelName: '觉瞳控制',
      channelDescription: '显示觉瞳控制会话和停止入口',
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      autoRunOnBoot: false,
      autoRunOnMyPackageReplaced: false,
      allowWakeLock: false,
      allowWifiLock: false,
    ),
  );
  runApp(const SatoriApp());
}

class SatoriApp extends StatelessWidget {
  const SatoriApp({super.key, this.previewClient, this.previewFontFamily});
  final ControlClient? previewClient;
  final String? previewFontFamily;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '觉瞳',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: previewFontFamily,
      scaffoldBackgroundColor: _background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _accent,
        brightness: Brightness.dark,
        surface: _surface,
        primary: _accent,
        secondary: _mint,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _background,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: const CardThemeData(
        color: _surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surfaceRaised,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 15,
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: _surface,
        indicatorColor: Color(0xFF393251),
      ),
    ),
    home: ControlShell(previewClient: previewClient),
  );
}

class ControlShell extends StatefulWidget {
  const ControlShell({super.key, this.previewClient});
  final ControlClient? previewClient;
  @override
  State<ControlShell> createState() => _ControlShellState();
}

class _ControlShellState extends State<ControlShell>
    with WidgetsBindingObserver {
  late final client = widget.previewClient ?? ControlClient();
  final host = TextEditingController();
  final minFields = List.generate(3, (_) => TextEditingController());
  final maxFields = List.generate(3, (_) => TextEditingController());
  final initialFields = List.generate(3, (_) => TextEditingController());
  final values = [0.5, 0.5, 0.5];
  int tab = 0;
  bool simulator = false;
  bool busy = false;
  bool resetStickOnRelease = true;
  DateTime? _lastJoystickSend;
  String? _joystickEndpoint;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    client.addListener(_refresh);
    _syncJoystickTarget();
  }

  void _refresh() {
    if (mounted) {
      _syncJoystickTarget();
      setState(() {});
    }
  }

  void _syncJoystickTarget() {
    final state = client.state;
    if (state['connection'] != 'connected') {
      _joystickEndpoint = null;
      return;
    }
    final endpoint = state['endpoint'].toString();
    if (_joystickEndpoint == endpoint) return;
    _joystickEndpoint = endpoint;
    final target = state['target'];
    if (target is List && target.length == 3) {
      for (var i = 0; i < 3; i++) {
        if (target[i] is num) {
          values[i] = ((target[i] as num) - 500) / 2000;
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) client.restore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    client.removeListener(_refresh);
    client.dispose();
    host.dispose();
    for (final field in [...minFields, ...maxFields, ...initialFields]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  SafetyProfile _profile() {
    if (simulator) return SafetyProfile.simulator();
    List<int> read(List<TextEditingController> fields) => [
      for (final field in fields) int.parse(field.text.trim()),
    ];
    return SafetyProfile(read(minFields), read(maxFields), read(initialFields));
  }

  Future<void> _discover() => _run(() async {
    if (!Platform.isAndroid) throw StateError('目前只验证 Android');
    final permission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      final granted =
          await FlutterForegroundTask.requestNotificationPermission();
      if (granted != NotificationPermission.granted) {
        throw StateError('请允许控制会话通知后重试');
      }
    }
    await client.start();
    await client.send('discover', {
      'host': host.text.trim().isEmpty ? null : host.text.trim(),
    });
  });

  Future<void> _select(Map endpoint) => _run(() async {
    final profile = _profile();
    await client.send('select', {
      'endpoint': Map<String, Object>.from(endpoint),
      'simulator': simulator,
      'profile': profile.toJson(),
    });
    if (mounted) {
      setState(() {
        tab = 0;
        for (var i = 0; i < 3; i++) {
          values[i] = (profile.initial[i] - 500) / 2000;
        }
      });
    }
  });

  void _sendJoystick(double x, double y, {bool force = false}) {
    if (busy) return;
    setState(() {
      values[0] = x;
      values[1] = y;
    });
    final now = DateTime.now();
    if (!force &&
        _lastJoystickSend != null &&
        now.difference(_lastJoystickSend!) < const Duration(milliseconds: 50)) {
      return;
    }
    _lastJoystickSend = now;
    client
        .send('manual', {
          'values': [x, y, -1],
        })
        .catchError((Object error) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(error.toString())));
          }
        });
  }

  void _releaseJoystick() {
    if (resetStickOnRelease) {
      _sendJoystick(.5, .5, force: true);
    } else {
      _sendJoystick(values[0], values[1], force: true);
    }
  }

  Widget _sectionTitle(String title, {String? description}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 23,
          fontWeight: FontWeight.w700,
          letterSpacing: -.4,
        ),
      ),
      if (description != null) ...[
        const SizedBox(height: 4),
        Text(description, style: const TextStyle(color: _muted)),
      ],
    ],
  );

  Widget _panel(Widget child, {Color color = _surface}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(24),
    ),
    child: child,
  );

  Widget _statusCard(Map<String, dynamic> state) {
    final connection = state['connection'] as String? ?? 'disconnected';
    final label = switch (connection) {
      'connected' => '已连接',
      'searching' => '正在发现',
      'found' => '发现设备',
      'no_results' => '未发现设备',
      'reconnecting' => '连接中断，恢复中',
      'failed' => '连接失败',
      _ => '尚未连接',
    };
    final active = connection == 'connected';
    final battery = state['battery'];
    final batteryTime = DateTime.tryParse(state['batteryAt']?.toString() ?? '');
    final stale =
        batteryTime != null &&
        DateTime.now().difference(batteryTime) > const Duration(seconds: 60);
    final endpoint = state['endpoint'];
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: active
                      ? _mint.withValues(alpha: .14)
                      : _accent.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  active ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                  color: active ? _mint : _accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      endpoint is Map
                          ? '${endpoint['host']}:${endpoint['port']}'
                          : '前往设备页发现现有网络中的觉瞳',
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (active) Icon(Icons.circle, color: _mint, size: 10),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _pill(
                '本地模式 · ${state['mode'] == 'auto' ? '自动' : '手动'}',
                Icons.tune_rounded,
              ),
              _pill(
                battery == null
                    ? '电量未知'
                    : '电量 $battery%${stale ? ' · 已过期' : ''}',
                Icons.battery_5_bar_rounded,
              ),
              if (state['simulator'] == true)
                _pill('模拟器', Icons.science_outlined),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: _surfaceRaised,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: _accent),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(fontSize: 12)),
      ],
    ),
  );

  Widget _controlPage(Map<String, dynamic> state) {
    final connected = state['connection'] == 'connected';
    final target = List<int>.from(
      state['target'] as List? ?? [1500, 1500, 1500],
    );
    return _page([
      _sectionTitle('控制', description: '看清状态，再开始动作'),
      const SizedBox(height: 18),
      _statusCard(state),
      const SizedBox(height: 22),
      if (!connected)
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '准备连接',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 7),
              const Text(
                '手机与觉瞳需要处于当前网络可达的环境。连接后不会自动运动。',
                style: TextStyle(color: _muted),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => setState(() => tab = 2),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('前往设备页'),
              ),
            ],
          ),
        ),
      if (connected) ...[
        _sectionTitle('手动控制', description: '摇杆实时控制方向；显示的是目标，不是位置遥测'),
        const SizedBox(height: 12),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '方向摇杆 · CH1 / CH2',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              JoystickPad(
                x: values[0],
                y: values[1],
                onChanged: (x, y) => _sendJoystick(x, y),
                onReleased: _releaseJoystick,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'CH1 ${target[0]} μs  ·  CH2 ${target[1]} μs',
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: busy
                        ? null
                        : () => _sendJoystick(.5, .5, force: true),
                    icon: const Icon(Icons.center_focus_strong_rounded),
                    label: const Text('方向回中'),
                  ),
                ],
              ),
              Material(
                color: Colors.transparent,
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('松手回中'),
                  subtitle: const Text('仅回中 CH1 / CH2，眼皮保持原值'),
                  value: resetStickOnRelease,
                  onChanged: (value) =>
                      setState(() => resetStickOnRelease = value),
                ),
              ),
              const Divider(height: 28),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '眼皮 · CH3',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '${target[2]} μs',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ),
              Slider(
                value: values[2],
                onChanged: busy ? null : (v) => setState(() => values[2] = v),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () => _run(
                          () => client.send('manual', {
                            'values': [-1, -1, values[2]],
                          }),
                        ),
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('发送眼皮目标'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: busy ? null : () => _run(() => client.send('stop')),
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('停止自动与动作'),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '停止只取消本地调度，不发送回中指令；设备不会回报位置。',
          style: TextStyle(color: _muted, fontSize: 12),
        ),
        const SizedBox(height: 22),
        _sectionTitle('持续行为', description: '锁屏时由后台会话持有'),
        const SizedBox(height: 12),
        _panel(
          Column(
            children: [
              _behaviorRow(
                Icons.explore_rounded,
                '自动转动',
                'CH1 / CH2 缓慢变化',
                state['autoRotate'] == true,
                (value) =>
                    _run(() => client.send('rotate', {'enabled': value})),
              ),
              const Divider(height: 28),
              _behaviorRow(
                Icons.visibility_rounded,
                '自动眨眼',
                'CH3 定时触发预设',
                state['autoWink'] == true,
                (value) =>
                    _run(() => client.send('winkAuto', {'enabled': value})),
              ),
            ],
          ),
        ),
      ],
    ]);
  }

  Widget _behaviorRow(
    IconData icon,
    String title,
    String detail,
    bool enabled,
    ValueChanged<bool> onChanged,
  ) => Row(
    children: [
      Icon(icon, color: _accent),
      const SizedBox(width: 13),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            Text(detail, style: const TextStyle(color: _muted, fontSize: 12)),
          ],
        ),
      ),
      Switch(value: enabled, onChanged: busy ? null : onChanged),
    ],
  );

  Widget _actionsPage(Map<String, dynamic> state) {
    final connected = state['connection'] == 'connected';
    final playing = state['playback'] == 'playing';
    return _page([
      _sectionTitle('动作', description: '保留觉瞳已有的眨眼预设'),
      const SizedBox(height: 18),
      _statusCard(state),
      const SizedBox(height: 22),
      for (final entry in [
        ('wink', '轻眨一下', '闭合 → 睁开', Icons.visibility_outlined),
        ('wink2', '连眨两下', '闭合 → 睁开 × 2', Icons.auto_awesome_rounded),
      ]) ...[
        _panel(
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(entry.$4, color: _accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.$2,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      entry.$3,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: '播放${entry.$2}',
                icon: const Icon(Icons.play_arrow_rounded),
                onPressed: connected && !busy && !playing
                    ? () => _run(() => client.send('play', {'name': entry.$1}))
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
      if (playing)
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '动作播放中',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                '设备没有动作完成确认；这里展示的是本地调度状态。',
                style: TextStyle(color: _muted),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: busy ? null : () => _run(() => client.send('stop')),
                icon: const Icon(Icons.stop_rounded),
                label: const Text('取消播放'),
              ),
            ],
          ),
        ),
      if (!connected)
        const Text('连接设备后可播放预设动作。', style: TextStyle(color: _muted)),
    ]);
  }

  Widget _devicePage(Map<String, dynamic> state) {
    final connected = state['connection'] == 'connected';
    final discovered = (state['discovered'] as List? ?? []).cast<Map>();
    final simulators = (state['simulators'] as List? ?? []).cast<Map>();
    return _page([
      _sectionTitle('设备', description: '发现、选择和诊断当前网络中的觉瞳'),
      const SizedBox(height: 18),
      _statusCard(state),
      const SizedBox(height: 18),
      if (connected)
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '当前控制会话',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 7),
              const Text(
                '断开后会停止本地调度，并尽力通知设备。',
                style: TextStyle(color: _muted),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => _run(() => client.send('disconnect')),
                  icon: const Icon(Icons.link_off_rounded),
                  label: const Text('断开控制会话'),
                ),
              ),
            ],
          ),
        ),
      if (!connected)
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '发现设备',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                '留空使用 UDP 广播；输入电脑局域网 IPv4 可直连模拟器。',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: host,
                enabled: !connected,
                decoration: const InputDecoration(
                  labelText: '指定 IPv4（可选）',
                  prefixIcon: Icon(Icons.lan_outlined),
                ),
              ),
              const SizedBox(height: 8),
              Material(
                color: Colors.transparent,
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('模拟器验证'),
                  subtitle: const Text('仅带标识的模拟器可用完整协议行程'),
                  value: simulator,
                  onChanged: connected
                      ? null
                      : (v) => setState(() => simulator = v),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy || connected ? null : _discover,
                  icon: const Icon(Icons.radar_rounded),
                  label: Text(
                    state['connection'] == 'searching' ? '正在搜索…' : '搜索现有网络',
                  ),
                ),
              ),
            ],
          ),
        ),
      if (!simulator && !connected) ...[
        const SizedBox(height: 20),
        _sectionTitle('真实设备安全范围', description: '连接前填写已确认的 PWM 值；初始目标须位于范围内'),
        const SizedBox(height: 12),
        _panel(
          Column(
            children: [
              for (var i = 0; i < 3; i++) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    ['CH1 · 左右', 'CH2 · 上下', 'CH3 · 眼皮'][i],
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final field in [
                      (minFields[i], '最小'),
                      (maxFields[i], '最大'),
                      (initialFields[i], '初始'),
                    ])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: TextField(
                            controller: field.$1,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: field.$2,
                              isDense: true,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (i < 2) const SizedBox(height: 16),
              ],
              const SizedBox(height: 12),
              const Text(
                '协议允许 500–2500 μs；实际机械安全范围请以设备校准为准。',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
      if (!connected) ...[
        const SizedBox(height: 20),
        _sectionTitle('发现结果'),
        const SizedBox(height: 10),
        if (discovered.isEmpty)
          _panel(
            Text(
              state['connection'] == 'no_results'
                  ? '没有找到设备。检查网络后可重新搜索。'
                  : '尚无发现结果。',
              style: const TextStyle(color: _muted),
            ),
          ),
        for (final endpoint in discovered) ...[
          _panel(
            Row(
              children: [
                Icon(
                  simulators.any(
                        (v) =>
                            v['host'] == endpoint['host'] &&
                            v['port'] == endpoint['port'],
                      )
                      ? Icons.science_outlined
                      : Icons.memory_rounded,
                  color: _accent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${endpoint['host']}:${endpoint['port']}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        simulators.any(
                              (v) =>
                                  v['host'] == endpoint['host'] &&
                                  v['port'] == endpoint['port'],
                            )
                            ? '已验证模拟器标识'
                            : '局域网设备',
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: busy || connected ? null : () => _select(endpoint),
                  child: const Text('连接'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
      const SizedBox(height: 20),
      const Text(
        '仅适用于可信局域网。断开报文为尽力发送；锁屏可靠性仍待觉瞳实机验证。',
        style: TextStyle(color: _muted, fontSize: 12),
      ),
    ]);
  }

  Widget _page(List<Widget> children) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: children,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = client.state;
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '觉瞳',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
            Text(
              '技术验证版 · Wi-Fi 控制',
              style: TextStyle(fontSize: 11, color: _muted),
            ),
          ],
        ),
        actions: [
          if (state['connection'] == 'connected')
            IconButton(
              tooltip: '停止自动与动作',
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: busy ? null : () => _run(() => client.send('stop')),
            ),
          IconButton(
            tooltip: '刷新后台状态',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => client.restore(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (client.message != null || state['error'] != null)
            Container(
              width: double.infinity,
              color: const Color(0xFF543037),
              padding: const EdgeInsets.all(10),
              child: Text(
                '${client.message ?? state['error']}',
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: tab,
              children: [
                _controlPage(state),
                _actionsPage(state),
                _devicePage(state),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (index) => setState(() => tab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.tune_rounded), label: '控制'),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            label: '动作',
          ),
          NavigationDestination(icon: Icon(Icons.devices_rounded), label: '设备'),
        ],
      ),
    );
  }
}
