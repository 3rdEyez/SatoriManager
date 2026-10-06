# 觉瞳 Flutter BLE 技术验证版

当前主入口已迁移至 BLE：多手机轮流直连、连接自动启用输出、三通道控制、自动转动/眨眼、预设和暂停。Android 前台服务独占蓝牙会话与动作引擎，页面恢复只同步状态。固件配套实现位于隔壁 ESP-3RDEYE；Qt 不参与此路径。

- [BLE 实现、Qt 功能对照与验收](docs/BLE_IMPLEMENTATION.md)
- [本机 Linux 蓝牙调试](BLE_LINUX.md)
- [共同字节协议](../docs/protocol/satori-ble-v1.md)

新设备默认首次配对码为 **123456**；已有设备升级保留原码与绑定。新版固件最多保存8台手机的配对，同一时间仅允许一台连接；空闲时新手机可用当前码配对加入，无需原手机开启换绑。当前已绑定手机可修改六位码，改码不撤销已有手机。满额不自动删除任何bond，清理通过USB维护。知道配对码即可加入，因此首次使用后建议修改默认码。

每次连接及重连都会自动ARM，并读取设备快照初始化目标；不会恢复上一次的预设或自动动作。默认范围和启动姿态已内置，普通用户无需填写。App沿用Qt的三通道逻辑输入500–2500，固件首次ARM使用[1500,1500,1500]并继续应用原有机械标定与限位；这些是产品默认参数，真机验收仍待完成。已有自定义范围/维护启动配置优先，损坏配置仍拒绝输出。自定义范围放在设备页折叠的“高级维护”中。用户在重连等待或建立期间暂停会撤销整轮恢复的自动启动，后续重试只恢复连接；显式新连接或之后独立发生的新断线恢复仍会自动启动。

交付安装包使用 `flutter build apk --release --split-per-abi`，ARM64 手机安装 `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`；32 位 ARM 设备使用对应 `armeabi-v7a` 包。Debug 通用包包含多架构调试引擎，只用于开发，不作为日常安装包。Gradle 模板指向 debug 签名，但最新已验证的本地 release APK 实际未签名，不能直接安装；正式签名尚未配置。覆盖安装须复用原 App 的签名身份，见 [签名兼容方案](../docs/apk-signing-compatibility.md)。

## 开发

在 `flutter_app/` 运行 `flutter pub get`、`flutter analyze`、`flutter test`。Android 调试构建使用 `flutter build apk --debug`；按架构构建安装包使用 `flutter build apk --release --split-per-abi`。保留的 UDP 编解码、模拟器和回归工具仅用于协议测试。

当前本地交付 APK 实查未签名；不能据构建配置声称已签名或可覆盖安装。机械运动、通知操作和长时间后台行为需要在目标设备上单独验收。
