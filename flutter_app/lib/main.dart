import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'core/safety_limits.dart';
import 'core/control_status.dart';
import 'infrastructure/reactive_ble_link.dart' show requestBlePermissions;
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
      allowWakeLock: true,
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
  final minFields = List.generate(3, (_) => TextEditingController());
  final maxFields = List.generate(3, (_) => TextEditingController());
  final values = [0.5, 0.5, 0.5];
  int tab = 0;
  bool busy = false;
  bool resetStickOnRelease = true;
  DateTime? _lastJoystickSend;
  DateTime? _lastEyelidSend;
  String? _joystickEndpoint;
  String? _localError;

  void _showError(Object error) {
    _localError = error.toString();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('操作未完成，请查看设备诊断信息')));
      setState(() {});
    }
  }

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
    if (state['connection'] != 'connected' ||
        state['outputAuthorized'] != true) {
      _joystickEndpoint = null;
      return;
    }
    final endpoint = state['deviceId'].toString();
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
    for (final field in [...minFields, ...maxFields]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      _localError = null;
    });
    try {
      await action();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  SafetyLimits _limits() {
    List<int> read(List<TextEditingController> fields) => [
      for (final field in fields) int.parse(field.text.trim()),
    ];
    return SafetyLimits(read(minFields), read(maxFields));
  }

  Future<void> _discover() => _run(() async {
    if (!Platform.isAndroid) {
      throw StateError('手机界面目前只验证 Android；本机请使用 BLE 调试工具');
    }
    if (!await requestBlePermissions()) throw StateError('请允许蓝牙权限后重试');
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
    await client.send('discover');
  });

  Future<void> _select(Map device) => _run(() async {
    await client.send('select', {'deviceId': device['id']});
    final limits = client.state['safety'];
    if (limits is Map) {
      for (var i = 0; i < 3; i++) {
        minFields[i].text = '${(limits['minimum'] as List)[i]}';
        maxFields[i].text = '${(limits['maximum'] as List)[i]}';
      }
    }
    if (mounted) setState(() => tab = 0);
  });

  Future<void> _arm() => _run(() => client.send('arm'));

  Future<void> _pause() async {
    try {
      await client.send('stop');
    } catch (e) {
      _showError(e);
    }
  }

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
        .catchError((Object error) => _showError(error));
  }

  void _releaseJoystick() {
    if (resetStickOnRelease) {
      _sendJoystick(.5, .5, force: true);
    } else {
      _sendJoystick(values[0], values[1], force: true);
    }
  }

  void _sendEyelid(double value, {bool force = false}) {
    if (busy) return;
    setState(() => values[2] = value);
    final now = DateTime.now();
    if (!force &&
        _lastEyelidSend != null &&
        now.difference(_lastEyelidSend!) < const Duration(milliseconds: 50)) {
      return;
    }
    _lastEyelidSend = now;
    client
        .send('manual', {
          'values': [-1, -1, value],
        })
        .catchError((Object error) => _showError(error));
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
    final label = controlStatus(state);
    final active = connection == 'connected';
    final battery = state['battery'];
    final batteryTime = DateTime.tryParse(state['batteryAt']?.toString() ?? '');
    final stale =
        batteryTime != null &&
        DateTime.now().difference(batteryTime) > const Duration(seconds: 60);
    final deviceId = state['deviceId'];
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
                  active ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
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
                    if (deviceId != null)
                      const Text(
                        '觉瞳',
                        style: TextStyle(color: _muted, fontSize: 12),
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
                battery == null
                    ? '电量未知'
                    : '电量 $battery%${stale ? ' · 已过期' : ''}',
                battery == null
                    ? Icons.battery_unknown
                    : Icons.battery_5_bar_rounded,
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
    final armed = state['outputAuthorized'] == true;
    final target = state['target'] as List?;
    return _page([
      _sectionTitle('控制'),
      const SizedBox(height: 18),
      _statusCard(state),
      const SizedBox(height: 22),
      if (!connected)
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '尚未连接觉瞳',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 7),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => setState(() => tab = 2),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('连接设备'),
              ),
            ],
          ),
        ),
      if (connected && !armed) ...[
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                controlStatus(state),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              if (state['controlPhase'] == 'paused' ||
                  state['controlPhase'] == 'actionFailed' ||
                  state['controlPhase'] == 'ready')
                FilledButton.icon(
                  onPressed: busy ? null : _arm,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    state['controlPhase'] == 'ready' ? '启用控制' : '恢复控制',
                  ),
                ),
              if (needsControlAttention(state))
                TextButton(
                  onPressed: () => setState(() => tab = 2),
                  child: const Text('查看详情'),
                ),
            ],
          ),
        ),
      ],
      if (connected && armed && target != null) ...[
        _sectionTitle('手动控制'),
        const SizedBox(height: 12),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('方向', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              JoystickPad(
                x: values[0],
                y: values[1],
                onChanged: (x, y) => _sendJoystick(x, y),
                onReleased: _releaseJoystick,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: busy
                        ? null
                        : () => _sendJoystick(.5, .5, force: true),
                    icon: const Icon(Icons.center_focus_strong_rounded),
                    label: const Text('复位方向'),
                  ),
                ],
              ),
              Material(
                color: Colors.transparent,
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('松手回中'),
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
                      '眼皮',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              Slider(
                key: const ValueKey('eyelid-slider'),
                value: values[2],
                onChanged: busy ? null : _sendEyelid,
                onChangeEnd: busy
                    ? null
                    : (value) => _sendEyelid(value, force: true),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _pause,
            icon: const Icon(Icons.stop_circle_outlined),
            label: Text(state['controlPhase'] == 'pausing' ? '暂停中…' : '暂停控制'),
          ),
        ),
        const SizedBox(height: 22),
        _sectionTitle('自动动作'),
        const SizedBox(height: 12),
        _panel(
          Column(
            children: [
              _behaviorRow(
                Icons.explore_rounded,
                '自动转动',
                state['autoRotate'] == true,
                (value) =>
                    _run(() => client.send('rotate', {'enabled': value})),
              ),
              const Divider(height: 28),
              _behaviorRow(
                Icons.visibility_rounded,
                '自动眨眼',
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
    bool enabled,
    ValueChanged<bool> onChanged,
  ) => Row(
    children: [
      Icon(icon, color: _accent),
      const SizedBox(width: 13),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      Switch(value: enabled, onChanged: busy ? null : onChanged),
    ],
  );

  Widget _actionsPage(Map<String, dynamic> state) {
    final connected =
        state['connection'] == 'connected' && state['outputAuthorized'] == true;
    final playing = state['playback'] == 'playing';
    return _page([
      _sectionTitle('动作'),
      const SizedBox(height: 18),
      _statusCard(state),
      const SizedBox(height: 22),
      for (final entry in [
        ('wink', '轻眨一下', Icons.visibility_outlined),
        ('wink2', '连眨两下', Icons.auto_awesome_rounded),
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
                child: Icon(entry.$3, color: _accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  entry.$2,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
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
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _pause,
                icon: const Icon(Icons.stop_rounded),
                label: const Text('取消播放'),
              ),
            ],
          ),
        ),
      if (!connected)
        const Text('连接设备后可播放动作。', style: TextStyle(color: _muted)),
    ]);
  }

  Future<void> _changePairingCode() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _PairingCodeDialog(),
    );
    if (code == null || !mounted) return;
    await _run(() => client.send('setPairingCode', {'code': code}));
  }

  Future<void> _openTransfer() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('更换主控手机'),
        content: const Text(
          '请先设置并记住非默认配对码。继续后会暂停动作并断开本手机，允许新手机在60秒内用新码配对。成功后旧手机失去控制权；超时仍保留旧绑定。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('开启60秒换绑'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run(() => client.send('openTransfer'));
    }
  }

  String _addressSuffix(Object? address) {
    final value = address?.toString() ?? '';
    return value.length > 5 ? value.substring(value.length - 5) : value;
  }

  void _showPairingHelp() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('配对帮助'),
        content: const Text(
          '新设备默认配对码：123456。修改过请使用新码。配对名额已满或需要清除绑定时，可使用 USB 维护工具。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Widget _devicePage(Map<String, dynamic> state) {
    final connected = state['connection'] == 'connected';
    final active =
        connected ||
        state['connection'] == 'connecting' ||
        state['connection'] == 'reconnecting';
    final armed = state['outputAuthorized'] == true;
    final discovered = (state['discovered'] as List? ?? []).cast<Map>();
    return _page([
      _sectionTitle('设备'),
      const SizedBox(height: 18),
      _statusCard(state),
      const SizedBox(height: 18),
      if (active)
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('觉瞳', style: TextStyle(fontWeight: FontWeight.w700)),
              Text(controlStatus(state), style: const TextStyle(color: _muted)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await client.send('disconnect');
                  } catch (e) {
                    _showError(e);
                  }
                },
                icon: const Icon(Icons.link_off),
                label: const Text('断开连接'),
              ),
            ],
          ),
        ),
      if (!active)
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '添加觉瞳',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
              ),
              const SizedBox(height: 8),
              const Text('连接后会启用舵机。', style: TextStyle(color: _muted)),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: busy || state['connection'] == 'searching'
                    ? null
                    : _discover,
                icon: const Icon(Icons.bluetooth_searching),
                label: Text(
                  state['connection'] == 'searching' ? '正在搜索…' : '搜索附近觉瞳',
                ),
              ),
              TextButton(
                onPressed: () => _showPairingHelp(),
                child: const Text('配对帮助'),
              ),
            ],
          ),
        ),
      if (!active && client.running)
        TextButton.icon(
          onPressed: () async {
            try {
              await client.send('disconnect');
            } catch (e) {
              _showError(e);
            }
          },
          icon: const Icon(Icons.bluetooth_disabled),
          label: const Text('断开连接'),
        ),
      if (!active) ...[
        const SizedBox(height: 20),
        _sectionTitle('发现结果'),
        const SizedBox(height: 10),
        if (discovered.isEmpty)
          _panel(
            const Text('尚无结果；请打开蓝牙并让设备保持可发现。', style: TextStyle(color: _muted)),
          ),
        for (final device in discovered) ...[
          _panel(
            Row(
              children: [
                const Icon(Icons.bluetooth, color: _accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${device['name'] ?? '觉瞳'}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '设备尾号 ${_addressSuffix(device['id'])}',
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: busy ? null : () => _select(device),
                  child: const Text('连接'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
      if (state['pairingNotice'] is String) ...[
        const SizedBox(height: 16),
        _panel(Text(state['pairingNotice'] as String)),
      ],
      if (connected) ...[
        const SizedBox(height: 20),
        _sectionTitle('配对与手机'),
        const SizedBox(height: 12),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                state['supportsSharedPairing'] == true
                    ? '最多保存 8 台手机，同一时间只能连接 1 台。'
                    : state['supportsOwnerManagement'] == true
                    ? '当前固件仅支持单手机绑定，更换手机需要开启换绑窗口。升级设备固件后可多手机轮流使用。'
                    : '此固件不支持在手机上管理配对，请先升级设备固件。',
                style: const TextStyle(color: _muted),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: busy || state['supportsOwnerManagement'] != true
                        ? null
                        : _changePairingCode,
                    icon: const Icon(Icons.key),
                    label: const Text('修改配对码'),
                  ),
                  if (state['supportsSharedPairing'] != true)
                    OutlinedButton.icon(
                      onPressed:
                          busy || state['supportsOwnerManagement'] != true
                          ? null
                          : _openTransfer,
                      icon: const Icon(Icons.phonelink_setup),
                      label: const Text('更换手机'),
                    ),
                  if (state['supportsSharedPairing'] != true)
                    TextButton(
                      onPressed:
                          busy || state['supportsOwnerManagement'] != true
                          ? null
                          : () => _run(() => client.send('cancelTransfer')),
                      child: const Text('取消换绑窗口'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
      if (active) ...[
        const SizedBox(height: 16),
        ExpansionTile(
          title: const Text('设备详情'),
          childrenPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text('固件版本：${state['firmware'] ?? '未知'}'),
            ),
          ],
        ),
      ],
      ExpansionTile(
        title: const Text('诊断信息'),
        childrenPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        children: [
          if (active) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text('设备地址：${state['deviceId'] ?? '未知'}'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('身份：${state['identity'] ?? '等待认证'}'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('会话：${state['sessionPhase'] ?? '等待连接'}'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('最近业务确认：${state['lastAckSequence'] ?? '未知'}'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('已执行序号：${state['lastAppliedSequence'] ?? '未知'}'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '已下发逻辑值（控制目标）：${state['validChannelMask'] == 7 ? state['lastCommanded'] : '未知'}',
              ),
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('实际机械位置：未知'),
            ),
          ],
          for (final device in discovered)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${device['name'] ?? '觉瞳'}：${device['id'] ?? '未知'} · ${device['rssi'] ?? '未知'} dBm',
              ),
            ),
          if (state['error'] != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text('设备错误：${state['error']}'),
            ),
          if (client.message != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text('后台错误：${client.message}'),
            ),
          if (_localError != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text('界面错误：$_localError'),
            ),
        ],
      ),
      const SizedBox(height: 20),
      ExpansionTile(
        title: const Text('高级维护'),
        children: [
          const Text('自定义逻辑范围（可选，暂停后修改）', style: TextStyle(color: _muted)),
          _panel(
            Column(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(['CH1 · 左右', 'CH2 · 上下', 'CH3 · 眼皮'][i]),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final field in [
                        (minFields[i], '最小'),
                        (maxFields[i], '最大'),
                      ])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: TextField(
                              controller: field.$1,
                              enabled: !armed,
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
                  const SizedBox(height: 12),
                ],
                const Text(
                  '默认逻辑范围沿用原客户端输入映射；实际机械限位由设备标定约束。这里仅供维护时覆盖。',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: busy || armed || !connected
                      ? null
                      : () => _run(
                          () => client.send('configureSafety', {
                            'limits': _limits().toJson(),
                          }),
                        ),
                  child: const Text('保存自定义范围'),
                ),
              ],
            ),
          ),
        ],
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
            Text('测试版', style: TextStyle(fontSize: 11, color: _muted)),
          ],
        ),
        actions: [
          if (state['connection'] == 'connected')
            IconButton(
              tooltip: '暂停控制',
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: _pause,
            ),
          IconButton(
            tooltip: '刷新状态',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => client.restore(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (needsControlAttention(state) ||
              (state['connection'] == 'failed') ||
              client.message != null ||
              _localError != null)
            Container(
              width: double.infinity,
              color: const Color(0xFF543037),
              padding: const EdgeInsets.all(10),
              child: Text(
                needsControlAttention(state)
                    ? controlStatus(state)
                    : state['connection'] == 'failed'
                    ? '连接失败，请查看诊断信息'
                    : '操作未完成，请查看设备诊断信息',
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

class _PairingCodeDialog extends StatefulWidget {
  const _PairingCodeDialog();

  @override
  State<_PairingCodeDialog> createState() => _PairingCodeDialogState();
}

class _PairingCodeDialogState extends State<_PairingCodeDialog> {
  final first = TextEditingController();
  final second = TextEditingController();
  final form = GlobalKey<FormState>();

  @override
  void dispose() {
    first.dispose();
    second.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('修改配对码'),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('已配对手机仍可连接。请保存新码，应用不会记录。保存会暂停控制。'),
            const SizedBox(height: 16),
            TextFormField(
              controller: first,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 6,
              decoration: const InputDecoration(labelText: '新的六位配对码'),
              validator: (value) {
                if (!RegExp(r'^[0-9]{6}$').hasMatch(value ?? '')) {
                  return '请输入六位数字';
                }
                if (value == '123456') return '不能使用默认码123456';
                return null;
              },
            ),
            TextFormField(
              controller: second,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 6,
              decoration: const InputDecoration(labelText: '再次输入新码'),
              validator: (value) => value == first.text ? null : '两次输入不一致',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) Navigator.pop(context, first.text);
        },
        child: const Text('暂停并保存'),
      ),
    ],
  );
}
