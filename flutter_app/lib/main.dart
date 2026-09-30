import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'core/control_status.dart';
import 'infrastructure/reactive_ble_link.dart' show requestBlePermissions;
import 'joystick_pad.dart';
import 'runtime/control_client.dart';
import 'satori_palette.dart';

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

  ThemeData _theme(SatoriPalette p, Brightness brightness) => ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: previewFontFamily,
    scaffoldBackgroundColor: p.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.button,
      brightness: brightness,
      surface: p.background,
      primary: p.button,
      onSurface: p.ink,
    ),
    textTheme:
        (brightness == Brightness.dark
                ? ThemeData.dark().textTheme
                : ThemeData.light().textTheme)
            .apply(
              bodyColor: p.ink,
              displayColor: p.ink,
              fontFamily: previewFontFamily,
            ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      surfaceTintColor: Colors.transparent,
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 5,
      activeTrackColor: p.purple,
      inactiveTrackColor: p.line,
      thumbColor: p.sliderThumb,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? Colors.white : p.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? p.button : p.line,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '觉之瞳',
    debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.system,
    theme: _theme(SatoriPalette.light, Brightness.light),
    darkTheme: _theme(SatoriPalette.dark, Brightness.dark),
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
  late final ControlClient client = widget.previewClient ?? ControlClient();
  SatoriPalette get p => SatoriPalette.of(context);
  final values = [0.5, 0.5, 0.5];
  int tab = 0;
  bool busy = false;
  bool resetStickOnRelease = true;
  bool? autoView;
  bool _automaticConnection = true;
  String? _selectionPending;
  String? _joystickEndpoint;
  String? _localError;
  DateTime? _lastJoystickSend;
  DateTime? _lastEyelidSend;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    client.addListener(_refresh);
    _syncJoystickTarget();
    if (!client.preview) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && client.state['connection'] == 'disconnected') {
          _discover();
        }
      });
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
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    _syncJoystickTarget();
    setState(() {});
    _tryAutoSelect();
  }

  void _syncJoystickTarget() {
    final state = client.state;
    if (state['connection'] != 'connected' ||
        state['outputAuthorized'] != true) {
      _joystickEndpoint = null;
      return;
    }
    final endpoint = state['deviceId']?.toString();
    if (_joystickEndpoint == endpoint) return;
    _joystickEndpoint = endpoint;
    final target = state['target'];
    if (target is List && target.length == 3) {
      for (var i = 0; i < 3; i++) {
        if (target[i] is num) {
          values[i] = (((target[i] as num) - 500) / 2000).clamp(0.0, 1.0);
        }
      }
    }
  }

  void _showError(Object error) {
    _localError = error.toString();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_localError!)));
      setState(() {});
    }
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
      if (mounted) {
        setState(() => busy = false);
        _tryAutoSelect();
      }
    }
  }

  Future<void> _discover() => _run(() async {
    _automaticConnection = true;
    _selectionPending = null;
    if (!Platform.isAndroid) throw StateError('目前仅支持 Android 手机连接觉瞳');
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
    if (client.state['connection'] == 'connected') return;
    await client.send('discover');
  });

  void _tryAutoSelect() {
    if (!_automaticConnection || busy || client.preview) return;
    final state = client.state;
    if (state['connection'] != 'searching') return;
    final discovered = state['discovered'];
    if (discovered is! List || discovered.isEmpty) return;
    final device = discovered.first;
    if (device is! Map || device['id'] is! String) return;
    final id = device['id'] as String;
    if (_selectionPending == id) return;
    _selectionPending = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _automaticConnection) {
        _run(() => client.send('select', {'deviceId': id}));
      }
    });
  }

  Future<void> _disconnect() async {
    _automaticConnection = false;
    try {
      await client.send('disconnect');
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _pause() async {
    try {
      await client.send('stop');
    } catch (error) {
      _showError(error);
    }
  }

  void _sendJoystick(double x, double y, {bool force = false}) {
    if (busy || client.state['outputAuthorized'] != true) return;
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

  void _sendEyelid(double value, {bool force = false}) {
    if (busy || client.state['outputAuthorized'] != true) return;
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

  Future<void> _setAutoView(bool value) async {
    if (value == (autoView ?? (client.state['mode'] == 'auto'))) return;
    if (!value &&
        (client.state['autoRotate'] == true ||
            client.state['autoWink'] == true)) {
      await _run(() async {
        if (client.state['autoRotate'] == true) {
          await client.send('rotate', {'enabled': false});
        }
        if (client.state['autoWink'] == true) {
          await client.send('winkAuto', {'enabled': false});
        }
      });
      if (client.state['autoRotate'] == true ||
          client.state['autoWink'] == true) {
        return;
      }
    }
    if (mounted) setState(() => autoView = value);
  }

  Widget _page(List<Widget> children) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(26, 4, 26, 24),
        children: children,
      ),
    ),
  );

  Widget _divider() => Divider(height: 1, thickness: 1, color: p.line);

  Widget _section(String title, {String? subtitle}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          color: p.ink,
        ),
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(color: p.muted, fontSize: 14)),
      ],
    ],
  );

  Widget _statusChip(Map<String, dynamic> state) {
    final connection = state['connection'] as String? ?? 'disconnected';
    final battery = state['battery'];
    final active = connection == 'connected';
    final batteryTime = DateTime.tryParse(state['batteryAt']?.toString() ?? '');
    final stale =
        batteryTime != null &&
        DateTime.now().difference(batteryTime) > const Duration(seconds: 60);
    return InkWell(
      onTap: () => setState(() => tab = 2),
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: p.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.circle,
              color: active
                  ? p.success
                  : connection == 'searching' || connection == 'connecting'
                  ? p.purple
                  : p.muted,
              size: 8,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                active ? '已连接 · 觉瞳 01' : controlStatus(state),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: p.ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (active) ...[
              const SizedBox(width: 8),
              Container(width: 1, height: 16, color: p.line),
              const SizedBox(width: 8),
              Icon(
                battery == null
                    ? Icons.battery_unknown_outlined
                    : Icons.battery_full_rounded,
                color: p.purple,
                size: 16,
              ),
              const SizedBox(width: 3),
              Tooltip(
                message: stale ? '电量数据已超过 1 分钟' : '设备电量',
                child: Text(
                  battery == null ? '—' : '$battery%',
                  style: TextStyle(
                    fontSize: 11,
                    color: p.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(String title, String subtitle, Map<String, dynamic> state) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      color: p.ink,
                      height: 1.08,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(color: p.muted, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _statusChip(state),
          ],
        ),
      );

  Widget _outlinedAction(
    String label,
    IconData icon,
    VoidCallback? onPressed, {
    bool danger = false,
  }) => SizedBox(
    height: 44,
    child: OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: danger ? p.pink : p.purple,
        backgroundColor: danger ? p.dangerBackground : p.purpleSoft,
        side: BorderSide(color: danger ? p.pink : p.softBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
      ),
    ),
  );

  Widget _controlPage(Map<String, dynamic> state) {
    final connected = state['connection'] == 'connected';
    final armed = state['outputAuthorized'] == true;
    final automatic = autoView ?? (state['mode'] == 'auto');
    return _page([
      _header('觉之瞳', '控制', state),
      if (!connected || !armed) ...[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: p.purpleSoft,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  connected
                      ? controlStatus(state)
                      : state['connection'] == 'searching'
                      ? '正在寻找觉瞳设备'
                      : state['connection'] == 'connecting'
                      ? '正在连接觉瞳设备'
                      : state['connection'] == 'failed'
                      ? '连接失败，请在设置中重试'
                      : '尚未连接觉瞳设备',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : connected
                    ? () => _run(() => client.send('arm'))
                    : () => setState(() => tab = 2),
                child: Text(connected ? '启用控制' : '查看连接'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
      ],
      Center(
        child: Container(
          height: 40,
          width: 205,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: p.segment,
            border: Border.all(color: p.line),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            children: [
              for (final option in [(true, '自动'), (false, '手动')])
                Expanded(
                  child: InkWell(
                    onTap: connected && armed && !busy
                        ? () => _setAutoView(option.$1)
                        : null,
                    borderRadius: BorderRadius.circular(99),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: automatic == option.$1
                            ? p.button
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        option.$2,
                        style: TextStyle(
                          color: automatic == option.$1
                              ? Colors.white
                              : p.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 25),
      if (!automatic) ...[
        Center(child: _section('方向摇杆', subtitle: '拖动控制左右与上下')),
        const SizedBox(height: 18),
        IgnorePointer(
          ignoring: !armed || busy,
          child: Opacity(
            opacity: armed ? 1 : .55,
            child: JoystickPad(
              x: values[0],
              y: values[1],
              onChanged: (x, y) => _sendJoystick(x, y),
              onReleased: () => _sendJoystick(
                resetStickOnRelease ? .5 : values[0],
                resetStickOnRelease ? .5 : values[1],
                force: true,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _divider(),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '松手回中',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '松开摇杆后自动回到中心',
                    style: TextStyle(color: p.muted, fontSize: 11),
                  ),
                ],
              ),
            ),
            Switch(
              value: resetStickOnRelease,
              onChanged: (value) => setState(() => resetStickOnRelease = value),
            ),
            const SizedBox(width: 8),
            _outlinedAction(
              '方向回中',
              Icons.center_focus_strong_rounded,
              armed && !busy ? () => _sendJoystick(.5, .5, force: true) : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _divider(),
        const SizedBox(height: 14),
        Row(
          children: [
            const Expanded(
              child: Text(
                '眼皮开合',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '${(values[2] * 100).round()}%',
              style: TextStyle(
                color: p.purple,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        Slider(
          key: const ValueKey('eyelid-slider'),
          value: values[2],
          onChanged: armed && !busy ? _sendEyelid : null,
          onChangeEnd: armed && !busy
              ? (value) => _sendEyelid(value, force: true)
              : null,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('闭合', style: TextStyle(color: p.muted, fontSize: 12)),
            Text('张开', style: TextStyle(color: p.muted, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: _outlinedAction(
            '眨眼',
            Icons.motion_photos_on_rounded,
            armed && !busy && state['playback'] != 'playing'
                ? () => _run(() => client.send('play', {'name': 'wink'}))
                : null,
          ),
        ),
      ] else ...[
        _section('自动控制', subtitle: '选择设备持续执行的动作'),
        const SizedBox(height: 20),
        _autoRow(
          '自动转动',
          '间隔改变方向',
          Icons.refresh_rounded,
          state['autoRotate'] == true,
          armed
              ? (value) => _run(() => client.send('rotate', {'enabled': value}))
              : null,
        ),
        _divider(),
        _autoRow(
          '自动眨眼',
          '间隔播放眨眼动作',
          Icons.motion_photos_on_rounded,
          state['autoWink'] == true,
          armed
              ? (value) =>
                    _run(() => client.send('winkAuto', {'enabled': value}))
              : null,
        ),
        const SizedBox(height: 20),
        Text('持续行为由本地控制会话调度。', style: TextStyle(color: p.muted, fontSize: 12)),
      ],
      if (connected && armed) ...[
        const SizedBox(height: 24),
        Center(
          child: TextButton.icon(
            onPressed: _pause,
            icon: const Icon(Icons.pause_circle_outline),
            label: const Text('暂停控制'),
          ),
        ),
      ],
    ]);
  }

  Widget _autoRow(
    String title,
    String subtitle,
    IconData icon,
    bool value,
    ValueChanged<bool>? onChanged,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: p.purpleSoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: p.purple),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              Text(subtitle, style: TextStyle(color: p.muted, fontSize: 12)),
            ],
          ),
        ),
        Switch(value: value, onChanged: busy ? null : onChanged),
      ],
    ),
  );

  Widget _actionsPage(Map<String, dynamic> state) {
    final ready =
        state['connection'] == 'connected' && state['outputAuthorized'] == true;
    final playing = state['playback'] == 'playing';
    return _page([
      _header('动作', '选择并播放预设', state),
      _divider(),
      const SizedBox(height: 20),
      _section('预设动作', subtitle: '当前可用的动作'),
      const SizedBox(height: 18),
      for (final entry in [
        ('wink', '轻眨一下', '闭合 → 睁开'),
        ('wink2', '连眨两下', '闭合 → 睁开 × 2'),
      ]) ...[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.$2,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.$3,
                      style: TextStyle(color: p.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: ready && !busy && !playing
                    ? () => _run(() => client.send('play', {'name': entry.$1}))
                    : null,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('播放'),
                style: FilledButton.styleFrom(
                  backgroundColor: p.button,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(100, 42),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ],
          ),
        ),
        _divider(),
      ],
      const SizedBox(height: 28),
      Text(
        playing
            ? '动作播放中'
            : ready
            ? '当前未播放动作'
            : '连接并启用控制后可播放动作',
        style: TextStyle(
          color: p.muted,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 4),
      Text('播放状态来自本地调度', style: TextStyle(color: p.muted, fontSize: 12)),
      if (playing) ...[
        const SizedBox(height: 14),
        _outlinedAction('取消播放', Icons.stop_rounded, _pause),
      ],
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

  Widget _settingRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Row(
      children: [
        Text(label, style: TextStyle(color: p.muted, fontSize: 15)),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  Widget _settingsPage(Map<String, dynamic> state) {
    final connected = state['connection'] == 'connected';
    final searching =
        state['connection'] == 'searching' ||
        state['connection'] == 'connecting' ||
        state['connection'] == 'reconnecting';
    return _page([
      _header('设置', '连接与设备', state),
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: p.purpleSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          '当前控制会话',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
      ),
      _settingRow('连接方式', '蓝牙 · BLE'),
      _divider(),
      _settingRow(
        '当前设备',
        connected
            ? '觉瞳 01'
            : searching
            ? '正在连接…'
            : '未连接',
      ),
      _divider(),
      if (connected) ...[
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: _outlinedAction(
            '断开控制会话',
            Icons.link_off_rounded,
            busy ? null : _disconnect,
            danger: true,
          ),
        ),
      ] else ...[
        const SizedBox(height: 16),
        Text(
          searching ? '正在自动发现并连接觉瞳设备…' : '未发现设备，请确认设备已开启且手机蓝牙可用。',
          style: TextStyle(color: p.muted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: _outlinedAction(
            '重新搜索',
            Icons.bluetooth_searching,
            busy || searching ? null : _discover,
          ),
        ),
        TextButton(onPressed: _showPairingHelp, child: const Text('配对帮助')),
      ],
      if (state['pairingNotice'] is String) ...[
        const SizedBox(height: 12),
        Text(
          state['pairingNotice'] as String,
          style: TextStyle(color: p.muted),
        ),
      ],
      if (connected) ...[
        const SizedBox(height: 28),
        _section('配对与手机'),
        const SizedBox(height: 10),
        Text(
          state['supportsSharedPairing'] == true
              ? '最多保存 8 台手机，同一时间只能连接 1 台。'
              : state['supportsOwnerManagement'] == true
              ? '当前固件仅支持单手机绑定，更换手机需要开启换绑窗口。'
              : '此固件不支持在手机上管理配对。',
          style: TextStyle(color: p.muted, fontSize: 13),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _outlinedAction(
              '修改配对码',
              Icons.key_rounded,
              busy || state['supportsOwnerManagement'] != true
                  ? null
                  : _changePairingCode,
            ),
            if (state['supportsSharedPairing'] != true)
              _outlinedAction(
                '更换手机',
                Icons.phonelink_setup_rounded,
                busy || state['supportsOwnerManagement'] != true
                    ? null
                    : _openTransfer,
              ),
            if (state['supportsSharedPairing'] != true)
              TextButton(
                onPressed: busy || state['supportsOwnerManagement'] != true
                    ? null
                    : () => _run(() => client.send('cancelTransfer')),
                child: const Text('取消换绑窗口'),
              ),
          ],
        ),
      ],
      const SizedBox(height: 20),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text('设备详情', style: TextStyle(color: p.ink)),
        children: [
          _settingRow('应用版本', '${state['appVersion'] ?? '未知'}'),
          _settingRow('固件版本', '${state['firmware'] ?? '未知'}'),
          _settingRow('应用 BLE 协议', '${state['appProtocol'] ?? '未知'}'),
          _settingRow('设备 BLE 协议', '${state['deviceProtocol'] ?? '未知'}'),
          _settingRow('控制状态', controlStatus(state)),
          if (state['error'] != null) _settingRow('设备错误', '${state['error']}'),
          if (client.message != null) _settingRow('后台错误', client.message!),
          if (_localError != null) _settingRow('界面错误', _localError!),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '设备实际姿态未回传',
              style: TextStyle(color: p.muted, fontSize: 12),
            ),
          ),
        ],
      ),
    ]);
  }

  Widget _bottomNav() => Container(
    decoration: BoxDecoration(
      color: p.background,
      border: Border(top: BorderSide(color: p.line)),
    ),
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            for (final item in [
              (0, '控制', Icons.tune_rounded),
              (1, '动作', Icons.play_arrow_rounded),
              (2, '设置', Icons.settings_outlined),
            ])
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => tab = item.$1),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 35,
                        height: 35,
                        decoration: BoxDecoration(
                          color: tab == item.$1 ? p.button : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          item.$3,
                          color: tab == item.$1 ? Colors.white : p.muted,
                          size: 23,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.$2,
                        style: TextStyle(
                          color: tab == item.$1 ? p.purple : p.muted,
                          fontSize: 12,
                          fontWeight: tab == item.$1
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = client.state;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (needsControlAttention(state) || state['connection'] == 'failed')
              Container(
                width: double.infinity,
                color: p.warningBackground,
                padding: const EdgeInsets.all(9),
                child: Text(
                  controlStatus(state),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.pink),
                ),
              ),
            Expanded(
              child: IndexedStack(
                index: tab,
                children: [
                  _controlPage(state),
                  _actionsPage(state),
                  _settingsPage(state),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _bottomNav(),
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
