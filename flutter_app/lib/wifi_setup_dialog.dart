import 'package:flutter/material.dart';
import 'core/lan_window.dart';

class WifiMaintenanceInput {
  const WifiMaintenanceInput(
    this.ssid,
    this.password, {
    this.rememberNetwork = false,
  });
  final bool rememberNetwork;
  final String ssid, password;
}

class WifiSetupDialog extends StatefulWidget {
  const WifiSetupDialog({super.key, this.canRememberNetwork = false});
  final bool canRememberNetwork;
  @override
  State<WifiSetupDialog> createState() => _WifiSetupDialogState();
}

class _WifiSetupDialogState extends State<WifiSetupDialog> {
  final _ssid = TextEditingController(), _password = TextEditingController();
  String? _error;
  bool _remember = false;
  @override
  void dispose() {
    _ssid.clear();
    _password.clear();
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  void submit() {
    try {
      LanWindowStatus.lanRequest(
        open: true,
        requestId: 1,
        windowId: 0,
        ssid: _ssid.text,
        password: _password.text,
      );
      final input = WifiMaintenanceInput(
        _ssid.text,
        _password.text,
        rememberNetwork: _remember,
      );
      _ssid.clear();
      _password.clear();
      Navigator.pop(context, input);
    } on FormatException {
      setState(() => _error = 'SSID须为1–32字节，WPA2密码须为8–63个ASCII字符。');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('连接局域网进行维护'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.canRememberNetwork
                ? '仅支持2.4GHz WPA2个人网络。默认只用本次，结束清除；选择记住后仅保存在设备，不保存到手机，以后仍需主动开启维护。'
                : '仅用于本次限时维护，结束后从设备内存清除；不保存到手机或设备持久存储。仅支持2.4GHz WPA2个人网络。',
          ),
          if (widget.canRememberNetwork)
            CheckboxListTile(
              title: const Text('记住此网络'),
              subtitle: const Text('密码存入设备本地配置；手机不保存。换网时可重新配置。'),
              value: _remember,
              onChanged: (v) => setState(() => _remember = v == true),
            ),
          TextField(
            controller: _ssid,
            decoration: const InputDecoration(labelText: 'Wi-Fi名称（SSID）'),
            autocorrect: false,
            enableSuggestions: false,
          ),
          TextField(
            controller: _password,
            obscureText: true,
            enableIMEPersonalizedLearning: false,
            decoration: const InputDecoration(labelText: 'Wi-Fi密码'),
            autocorrect: false,
            enableSuggestions: false,
          ),
          if (_error != null) Text(_error!),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: submit, child: const Text('连接网络并开启维护')),
    ],
  );
}
