# 觉瞳 Flutter 阶段 A 与三页界面

基线：Qt 仓库 `e7e09d4b09deff4f4e09e913edf161be827c591d`。本工程是 Android Wi-Fi/UDP 技术验证版；未经过实际觉瞳和锁屏验收，不能代替旧客户端。Flutter 3.44.9 / Dart 3.12.2，`flutter_foreground_task` 11.0.3；Android Gradle Plugin 9.0.1、Gradle 9.1.0、Kotlin 2.3.20、compile SDK 36、NDK 28.2.13676358。原 Qt 工程保留。

界面已重构为“控制 / 动作 / 设备”三页，共用同一个后台状态。深色视觉方向保留旧版紫色线索，连接、电量和动作状态都有文字说明。控制页可切换自动行为，方向摇杆实时控制 CH1/CH2，松手默认回中，也可关闭松手回中或点击“方向回中”；眼皮 CH3 单独发送，方向操作不修改 CH3。回中目标受真实设备安全范围约束，且不等同于“停止动作”；动作页播放或取消现有 `wink`、`wink2`；设备页发现网络端点并配置真实设备安全范围。界面预览来自 Flutter 实际渲染，使用带“模拟器”标识的样本状态，可通过 `flutter test tool/render_previews_test.dart --update-goldens` 重新生成到 `build/design_preview/`。此预览脚本需要本机安装 Noto Sans CJK 字体。

## 运行

1. 安装 Flutter 3.44.9、JDK 17 和 Android SDK；在 `flutter_app/` 执行 `flutter pub get`、`flutter run`，或 `flutter build apk --debug`。
2. 模拟器在电脑运行：`dart run tool/satori_simulator.dart --bind 0.0.0.0`。手机和电脑须在可达的同一局域网。在 App 的地址框输入电脑局域网 IPv4，勾选“模拟器验证”，点击“发现设备”，然后选择有模拟器标识的端点。`--drop-every 2` 每两包丢一包；`--silent-after 3` 在第 3 包后停止应答；`--malformed` 返回非法响应。模拟器输出带 UTC 时间戳的原始字节和文本。
3. 连接真实觉瞳时不勾模拟器；输入已确认安全的 CH1/2/3 最小值、最大值和初始目标后再选设备。应用连接成功时不发送运动报文。先在安全行程内小幅手动操作。
4. “停止动作”只取消本地调度；“断开连接”尽力发送 `SatoriEye_DISCONNECT` 并清空会话。固件可能仍在执行已收到的平滑移动。UI 显示的是发送目标，不是舵机实际位置。

## 已核对的协议与行为

- 发现 `SatoriEye_DISCOVERY_REQUEST` → UDP 8888；接收绑定 UDP 8889。发现响应来自设备发送端点，电量字段缺失或非法显示未知。模拟器单独附加 `,SIMULATOR` 标识；真实固件不需要变更。
- 心跳 `SatoriEye_HEARTBEAT_REQUEST/RESPONSE`；只有当前端点的合法响应才算存活。60 秒未收到响应进入恢复，向原端点每 10 秒尝试一次，最多 5 次；恢复后自动动作保持停止，需要用户重新开启。UDP 未提供设备身份认证，因此只在可信局域网使用。
- 手动/自动是客户端模式。发包保留 `CH1:<n>CH2:<n>CH3:<n>`、`SMOOTH:...MS:<ms>`。动作帧中 `-1` 保留当前通道；`duration` 是帧间等待，平滑时长仍为 200 ms。没有遥测协议。
- 相较旧版，取消不再阻塞线程；心跳超时按收到的响应计算；主动断开后可以重新发现。旧版睡眠唤醒行为尚无证据，本版不提供睡眠按钮。
- 阶段 A 自动转动使用固定 5 秒间隔、中心附近均匀随机目标，自动眨眼也使用固定 5 秒间隔；旧版的正态分布、范围、间隔参数和眨眼抖动留待阶段 B 迁移。所有目标仍受用户填写的安全范围限制。

## 验证与待办

`dart format --output=none --set-exit-if-changed lib test tool`、`flutter analyze`、`flutter test`、`flutter build apk --debug`。测试包括协议、模拟器标识、安全范围、定时取消、错误端点过滤、失联恢复、真实 UDP 环回。

真机待验证：前台手动/自动/眨眼、30 分钟和 2 小时无调试器锁屏、切换 App、网络中断、通知停止、划掉任务、系统回收及强制停止。记录手机型号、Android 版本、App commit、固件版本、网络拓扑和省电设置。模拟器通过不表示觉瞳或锁屏通过。
