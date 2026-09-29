# BLE A0/A1 implementation and acceptance

This is the Flutter replacement path for Qt. It is a development release, not a
claim of verified wearable or Android lock-screen operation.

## Ownership and flow

The Android `connectedDevice` foreground service creates one FlutterEngine-owned
`ReactiveBleLink`, `DeviceSession`, and `ControlEngine`. The visible UI requests
permissions, starts that service, and exchanges semantic commands and versioned
snapshots. UI recreation does not transfer a connection or restart actions.

The flow is scan → connect → protected access/system pairing → authenticated
identity check → EventTX subscription → CLAIM → load built-in or saved limits → automatic ARM.
Every reconnect also requests ARM, without replaying prior actions. A pause cancels
the pending start throughout the current recovery round, including backoff and
failed attempts. Built-in product defaults remove mandatory setup. Explicit malformed board
configuration still keeps output paused with an explanation. The App reads the
resulting three-channel state before merging any partial movement. The built-in startup [1500,1500,1500] derives from the production Qt client;
it is not presented as measured mechanical validation.

The service holds a CPU wake lock for its user-started lifetime so its heartbeat
and action timers can run with the screen off. It holds no Wi-Fi lock and does
not restart on boot or package replacement. Ending the service releases the lock.
Battery impact, Doze and OEM lifecycle behavior still require real Android tests.

Android's notification subscription API in the chosen BLE plugin has no explicit
CCCD-ready callback. Pairing is completed through protected access before command
timers start. CLAIM setup must tolerate a bounded SUBSCRIPTION_REQUIRED response;
no other command rejection is treated as success or silently downgraded.

## Control semantics

- Wire values 500–2500 are **logical input encoding**, not final servo pulse widths.
- UI target, firmware last-commanded values, and physical position are different.
  Physical position and unsampled battery are unknown.
- Commands have both GATT completion and protocol business ACK. Neither proves
  physical arrival. HALT confirmation means interpolation was cancelled.
- Manual input has one pending latest target, max 20 Hz, and one GATT writer.
- Presets preserve keyframes, wait for acceptance and keep their own `duration`;
  transition defaults to 200 ms. More than 100 ms late cancels the remaining preset.
- Manual takeover cancels prior actions. Pause clears pending targets/timers and
  asks firmware to hold its last legal output; it does not center or open the lid.
- Disconnect clears all scheduling. Retry delays are 1/2/4/8 seconds, then manual
  retry. Reconnected sessions request ARM automatically and never replay prior frames.

## Devices and limits

Pairing secrets and OS bond keys are not stored in Flutter preferences. Preferences
contain only authenticated identity, last radio address/name and user-confirmed
logical limits. A radio address/name is not an authentication credential. Lost
system bonding requires the documented USB maintenance flow; reinstalling this
App is not a device reset.

Set all three safe ranges in the device page. Firmware owns startup posture and
mechanical calibration. Invalid or absent firmware configuration makes ARM fail
with NOT_CONFIGURED, while scanning, pairing and status diagnostics remain usable.

## Qt replacement matrix

| Original capability | This BLE slice | Remaining work |
|---|---|---|
| Discovery / connection | BLE device page, authenticated identity, automatic ARM after safety checks | Real phone/device qualification |
| Manual CH1/CH2/CH3 | Joystick, lid control, local confirmed limits | Physical small-travel validation |
| Auto/Manual | Dart engine and manual takeover | Final parameter UX |
| Automatic eye movement | Bounded center-region random movement, fixed 5 s interval | Legacy normal distribution/range/interval options |
| Automatic blinking | Existing wink/wink2, fixed 5 s interval | Legacy random blink interval/jitter |
| Bundled wink/wink2 | Preserved JSON proportions/-1 and frame timing | Physical observation |
| External preset JSON loading | Parser retained, bundled presets usable | User file import UI |
| Cancel / disconnect | Firmware HALT/RELEASE confirmation plus local cancellation | Notification and radio-loss hardware matrix |
| Battery | Unknown without actual sampling | Hardware sampling if available |
| UDP / existing firmware | Codec, simulator and legacy engine retained for regression | Optional Flutter product UDP entry in later phase |
| Sleep | Not exposed; no verified firmware contract | Separate capability/protocol design if needed |
| Joystick release recenter toggle | Retained on the Flutter control page; uses confirmed safe ranges | Preference persistence remains later work |
| FacialRecognition mode button | No BLE operation; Qt has a mode request, no vision pipeline in this repo | Camera/vision feature and firmware contract are out of scope |
| Pupil-size dial | Qt display-only dial has no channel handler; not presented as a working BLE capability | Hardware/protocol support required |
| Settings “save” button | Qt handler only logged a message; BLE stores authenticated identity and confirmed safety limits | Persist remaining local Auto/joystick preferences later |
| Heartbeat / lost-connection recovery | BLE lease plus bounded reconnect and automatic ARM, no action replay | Radio-loss hardware acceptance |
| Background operation | Single service-owned runtime and notification actions | Android lock-screen/Doze acceptance |

The matrix was checked against `SatoriManagerContent/mobileclient.h`,
`mobileclient.cpp`, `ScreenMain.qml`, `ScreenControlForm.ui.qml`, `Setting.qml`,
`SettingForm.ui.qml`, `ControlStick.qml`, and `ActionPresetLoader.cpp`. It includes
placeholder controls separately from implemented Qt behavior.

Qt source is retained for history. Qt is not required to operate the BLE client.
The BLE firmware is not compatible with Qt/UDP at runtime. Recovery uses the
separate legacy firmware build or a previously backed-up image.

## Reproducible checks

From `flutter_app/` with the pinned Flutter SDK on PATH:

```sh
dart run tool/check_ble_contract.dart
dart run tool/ble_simulator.dart --drop-first-ack
dart run tool/ble_simulator.dart --unconfigured
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed lib test tool
flutter build apk --release --split-per-abi
dart run tool/ble_probe.dart --help
```

Use the Linux probe for a real BLE central and the fake peripheral for deterministic
protocol faults. One local Bluetooth adapter alone does not establish a two-device
radio test. See BLE_LINUX.md for BlueZ operation.

The Android adapter in `flutter_reactive_ble` 5.6.0 requires compile SDK 37,
so `android/app/build.gradle.kts` now sets `compileSdk = 37`. The supplied SDK
manager reports its valid platform package under `platforms/android-37.0`,
while Gradle looks up `android-37`. On this toolchain, a local symbolic link
from `platforms/android-37` to the actual SDK-managed `android-37.0` directory
lets Gradle find the same `android.jar` and package metadata. Do not fabricate
or edit platform metadata; use the official SDK package and only add this path
alias when that naming mismatch occurs.

Initial debug-build validation (2026-09-29; superseded for delivery by the release build below): Flutter 3.44.9 / Dart 3.12.2,
Temurin JDK 17.0.20.1, Gradle 9.1.0, AGP 9.0.1, Android compile SDK 37.
`dart format --output=none --set-exit-if-changed lib test tool`,
`flutter analyze`, `flutter test`, and `flutter build apk --debug` all passed;
59 Flutter tests passed. The debug APK for version `0.2.0+2` is
`build/app/outputs/flutter-apk/app-debug.apk` (173,337,677 bytes), SHA-256
`dabb37022d28e90eb7e0b9be784f460488b387e8477d5cb8da47c22ee97489b8`.
Gradle emits an informational warning that `device_info_plus` applies the
Kotlin Gradle Plugin and may need migration in a future Flutter release. This
build validates compilation only, not phone pairing, lock-screen operation,
or hardware behavior.

## Hardware acceptance still required

Record phone model/OS, exact App/firmware hashes, board configuration hash, supply
and default power-saving settings. Confirm SC Passkey and refusal of a second
phone, MTU 23, no PWM before ARM, NOT_CONFIGURED behavior, persistent bond after
reboot/update, safe small motion, stopped-output behavior on HALT/disconnect/lease,
and USB recovery preserving calibration.

Then test 30 minutes locked, 2 hours normal battery-powered use, camera switching,
UI recreation, Doze, notification pause/disconnect and 100 reconnects. Capture
firmware receipt/execution evidence and distinguish it from phone send logs.
Forced stop and process death are separate from ordinary lock-screen tests.


## APK 体积修正：release 按架构交付

初次交付的 173337677 字节 debug 通用包不适合作为日常安装包，已由按 ABI 拆分的 release 包替代。构建命令为 `flutter build apk --release --split-per-abi`。启用 `packaging.jniLibs.useLegacyPackaging = true`，让直接分发的 APK 压缩原生库；Android 安装时解压，下载体积减少不等于安装占用同步减少。

| 架构 | APK 字节数 | SHA-256 |
|---|---:|---|
| arm64-v8a | 8601827 | `d5786047d70ac7ed2a7834f73366f79bd28838b71b456d4c7a0297aa3dfe4b03` |
| armeabi-v7a | 8081805 | `239fd685033d4175e7982c1d82ab5f4e29d00ac3994764b3749b14508fa1d1a2` |
| x86_64 | 8777186 | `c2279349ea5e5f60752cf447ea227657c8f9452c8af8c3a13a92817c41926b26` |

默认交付 ARM64 包 `app-arm64-v8a-release.apk`，约 **8.6 MB**，较原 debug 包减少约 **95%**；32 位 ARM 包约 8.1 MB。三个 APK 分别只包含自身架构，不再携带 debug kernel blob。APK ZIP 完整性、原生库压缩状态及 ARM64 APK v2 签名验证通过，manifest 的 `extractNativeLibs=true` 与压缩方式一致，release 未设置 debuggable。

当前 ARM64 Flutter 引擎原生库压缩后仍为 5409708 字节，应用 AOT 库压缩后为 2125820 字节，因此保持当前 Flutter 实现不能把独立 APK 压到 1–2 MB。此处仅调整构建和交付方式，没有删减 BLE 或后台功能。release 仍使用开发签名；真实手机上的 release 生命周期验证与既有硬件待验项保持待验。


## 0.2.1 historical：默认初次码与手机管理配对

用户授权采用无按钮、不改硬件的流程：健康且完全未初始化的设备自动创建随机身份，首次配对码为 **123456**；首台通过 SC Passkey 配对的手机成为唯一主控。已有设备升级不会重置身份、码或绑定，损坏的 NVS/半初始化记录不会触发自动开放或擦除。默认码是公开引导值，不能防止首次被附近第三方抢先绑定；设备首次通电应在用户在场时完成绑定。

手机设备页提供：

1. **修改配对码**：隐藏输入、二次确认、保留前导零；先暂停，只有设备确认持久化后显示成功。当前手机的 bond 保留。不能重新设置123456，App 不把新码写入偏好、快照或错误日志。
2. **更换手机**：必须先改掉默认码；暂停后开启60秒窗口并断开旧手机，旧手机不自动重连。新手机完成认证且新主控持久化后才撤销旧 bond。
3. **取消换绑窗口**：旧手机重新连接后可取消；超时/重启均保留尚未被成功替换的旧主控。窗口内改码返回BUSY，先取消再修改。

此扩展使用同一20字节帧的opcode8/9/10及能力bit7，协议minor=1。旧固件不支持时，App禁用相应入口。使用此流程需要升级配套固件；只安装新APK不能让旧固件支持默认码或远程改码。主控手机丢失或系统bond失效仍通过USB维护恢复。曾经被撤销的手机再次作为“新手机”加入时，可能需要先在Android系统中忘记旧配对。

UI运行时代际检查在暂停完成后和实际发送管理帧前各执行一次：已经退休的旧界面不能在新界面接管后完成改码/换绑。管理命令使用同字节重试、持久化后业务ACK和响应缓存；OPEN成功后的断链被视为预期退出，不会自动恢复运动。

### App 验证与产物

Flutter格式检查（32文件）、完整analyze与全部 **80项测试** 通过。新增覆盖v1.1的4个命令、3个事件、6个拒绝向量；管理授权、存储失败、幂等重试、窗口超时/重启、取消后改码、旧UI在途命令取消、隐藏输入/确认及换绑不重连。

`flutter build apk --release --split-per-abi` 通过，版本 **0.2.1+3**。保留原生库压缩，未删减功能：

| 架构 | 字节数 | SHA-256 |
|---|---:|---|
| ARM64 | 8667431 | `fdc375239b31e9314e4cf9b947bc70cae4d2adbbce7f6ec8a3f826377c4d4bcf` |
| ARM32 | 8150917 | `1cd31185e596b7784ce03a236d922f518ac96c931821f892e2d3d4f22a01e23e` |
| x86_64 | 8843970 | `d11cbfec7a147af0dee3b296be53f25ac2177abcb01eda47f5a08564df92edd4` |

ARM64 APK v2签名验证通过（现有开发签名）；包内原生库确认为Deflate压缩。配对、改码及换绑的Android/ESP真机组合仍待实测，本次未烧录或驱动硬件。


## 0.2.2 shared pairing and automatic output

The new firmware advertises capability bit8, protocol minor2 and security policy2.
It stores up to eight authenticated SC bonds, with one live connection. A new phone
can pair with the current code while the device is idle; a connected phone prevents
other connections. No transfer window or automatic bond eviction is used. Existing
bonds survive code changes and upgrades. The UI retains the transfer controls only
for older single-owner firmware and hides them for shared-pairing devices.

The service resolves saved limits using the authenticated identity before
auto-start, falling back to the built-in satori_c3_v1 logical range 500..2500.
The firmware uses the corresponding built-in startup posture unless maintenance
configuration overrides it. Existing mechanical calibration and physical clamps
remain in effect. No mandatory end-user configuration is shown; optional range
overrides live in a collapsed maintenance section. Explicit pauses cancel pending starts across the current recovery round;
its retries may restore connectivity but cannot reauthorize output. An explicit
new connection or independent later loss starts a new recovery intent. Historical records below
or in the report describing paused reconnects apply to previous releases only.
