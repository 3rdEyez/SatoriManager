# 觉瞳 Flutter BLE 技术验证版

当前主入口已迁移至 BLE：多手机轮流直连、连接自动启用输出、三通道控制、自动转动/眨眼、预设和暂停。Android 前台服务独占蓝牙会话与动作引擎，页面恢复只同步状态。固件配套实现位于隔壁 ESP-3RDEYE；Qt 不参与此路径。

- [BLE 实现、Qt 功能对照与验收](docs/BLE_IMPLEMENTATION.md)
- [本机 Linux 蓝牙调试](BLE_LINUX.md)
- [共同字节协议](../docs/protocol/satori-ble-v1.md)
- [既有硬件记录](HARDWARE_VALIDATION.md)

新设备默认首次配对码为 **123456**；已有设备升级保留原码与绑定。新版固件最多保存8台手机的配对，同一时间仅允许一台连接；空闲时新手机可用当前码配对加入，无需原手机开启换绑。当前已绑定手机可修改六位码，改码不撤销已有手机。满额不自动删除任何bond，清理通过USB维护。知道配对码即可加入，因此首次使用后建议修改默认码。

每次连接及重连都会自动ARM，并读取设备快照初始化目标；不会恢复上一次的预设或自动动作。默认范围和启动姿态已内置，普通用户无需填写。App沿用Qt的三通道逻辑输入500–2500，固件首次ARM使用[1500,1500,1500]并继续应用原有机械标定与限位；这些是产品默认参数，真机验收仍待完成。已有自定义范围/维护启动配置优先，损坏配置仍拒绝输出。自定义范围放在设备页折叠的“高级维护”中。用户在重连等待或建立期间暂停会撤销整轮恢复的自动启动，后续重试只恢复连接；显式新连接或之后独立发生的新断线恢复仍会自动启动。

交付安装包使用 `flutter build apk --release --split-per-abi`，ARM64 手机安装 `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`；32 位 ARM 设备使用对应 `armeabi-v7a` 包。Debug 通用包包含多架构调试引擎，只用于开发，不作为日常安装包。当前 release 使用开发签名，正式发布签名尚未配置。

以下为迁移前 UDP 阶段记录，适用于保留的 legacy 回归代码，不代表当前 BLE 产品入口或 BLE 固件兼容性。

---

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

真机待验证：前台手动/自动/眨眼、30 分钟和 2 小时无调试器锁屏、切换 App、网络中断、通知停止、划掉任务、系统回收及强制停止。记录手机型号、Android 版本、App commit、固件版本、网络拓扑和省电设置。模拟器通过不表示觉瞳或锁屏通过。当前硬件串口诊断证据和剩余验收步骤见 [HARDWARE_VALIDATION.md](HARDWARE_VALIDATION.md)。
