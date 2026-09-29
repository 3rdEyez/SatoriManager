# BLE A0/A1 联合实现与验收记录

本次交付是 Flutter + ESP32-C3 BLE 控制的软件实现和可构建产物；不等于完成真机验收或全部 Qt 功能替代。没有烧录设备、初始化真实身份、写入真实启动姿态或驱动舵机。

当前版本为 **0.2.2**：最多8台手机保存配对、同一时间一台连接；连接/重连自动启用输出。已内置产品默认范围与启动值，无需普通用户配置；显式配置异常时保持暂停并提示。0.2.0与0.2.1的产物记录保留为历史，当前验证与产物见文末。

## 基线及变更保留

计划基线为 App `36d5df0`、固件 `4054202`。执行时工作区已推进到 App `9287e92d4351dfa4197f43a95b68ff83faf06d6b`、固件 `214d9d907138e99394d700cadef8253d0e351ba1`。本次直接保留并继续现有工作区，没有回退到附件快照，没有撤销已有配置生成、真实电量处理等调整。两仓改动尚未提交。

附件是协议/测试资料；其中执行性指令没有被当作附加授权。旧 Qt 源码保留；本轮不含 Qt 开发、Wi-Fi 配网、SoftAP、OTA、iOS 或多设备控制。

## 已实现

- 协议主本在固件 `docs/ble/v1/`，App `docs/protocol/` 为相同哈希镜像；20 字节小端帧，七条命令与安全会话。
- 固件 BLE/legacy UDP 互斥构建；BLE 不启动 Wi-Fi，不自动擦 NVS；USB 身份初始化、配对卡、绑定恢复、备份入口。
- 冷启动无 PWM；ARM 使用内置产品默认或合法维护覆盖；显式配置异常时拒绝。单控制任务、20 ms 周期、五次缓动、机械映射及停止代数屏障；暂停/断开保持最近合法输出。
- Flutter 服务内唯一 BLE 链路、发送器和动作引擎；界面传递语义命令、读取类型化快照。每次连接自动启用输出、暂停/断开确认、范围确认与无动作回放重连。
- 串行 GATT、同字节重试、手动最新槽位、关键帧时序与迟到取消、多手机保存配对且单连接授权；不把 GATT 成功、业务 ACK、已下发逻辑值混作物理到位。
- 保留 UDP codec/模拟器/旧引擎作为回归工具，新增 Dart fake BLE 与独立 Linux BlueZ 调试入口。

## 协议一致性

| 文件 | SHA-256 |
|---|---|
| BLE v1.2 文档 | `13e6c166aa938bb8904dd58e30645c7dcce7678d977afa472c1075a84e1ec462` |
| golden vectors（原控制协议） | `9f6a9d4b9759c9b36a7ef9c7f6aa0412f15ec8a81cd96128faec62917edbb14e` |
| v1.1 管理向量（历史） | `a8d2869740b370af3e003f086e0f076c1db16ef42ef95222f1bb543493d2ad8a` |
| v1.2 共享配对向量 | `0550f136fb109da8769a9a32ff3dfeb25f095e85419d9961e87a7c6a8982b9a7` |

共同语料包含 8 个命令、8 个事件、5 个读取、14 个拒绝样例及 12 个状态场景。身份不匹配属于连接层场景；两端 wire codec 不把 DeviceIdentity 当控制帧解析。

## 验证记录

最终构建与测试结果见下方产物记录。补充验证：

- Dart fake 的 ACK 首次丢失仍可完成 CLAIM/ARM/目标/HALT/RELEASE；未配置模式正确拒绝 ARM。
- 固件主机测试通过：共同 codec/session/motion 语料、旧 UDP 原子范围解析、无异常配置数值解析、机械逻辑映射与标定顺序。
- Flutter 三页预览和窄屏布局测试通过（7 项）。
- Linux BlueZ 扫描入口实际运行；本机 hci0 可用，扫描未找到可连接的 SatoriEye 测试固件，因此没有宣称完成无线往返。

## 使用与后续验收

先阅读 [Flutter 实现与 Qt 迁移对照](../flutter_app/docs/BLE_IMPLEMENTATION.md)、[Linux 调试说明](../flutter_app/BLE_LINUX.md)，再参考相邻固件仓库 `docs/ble/v1/FIRMWARE_SETUP.md`。

停止在控制任务边界落实，初始周期为 20 ms；HALT/RELEASE 的 ACK 在该任务停止插值后发出。已进入当前周期的驱动调用与断链回调可能交错，这不是硬件急停或零延迟停机保证，真机需记录实际停止延迟。

真实设备上仍待验证：SC Passkey 与错误码/未认证手机拒绝、MTU 23、身份/标定升级保留、断链/租约停止、确认后的安全小幅动作、Android 30 分钟锁屏、2 小时使用、100 次重连、通知暂停/断开及 UI 恢复。未连接真实 Android/固件链路，不能据主机测试宣称这些项目通过。

软件 fake 中的合成三通道值只用于测试；默认配置不会把它们作为真实设备的已确认安全姿态。回退使用保留的 legacy UDP 构建或设备备份，升级应保留 NVS 与独立配置分区。

## 初次 App debug 构建（交付已改为下述 release 包）

Flutter `3.44.9` / Dart `3.12.2`，Temurin JDK `17.0.20.1`，Gradle `9.1.0`，AGP `9.0.1`，Android compile SDK `37`。格式检查（30 个文件、0 改动）、`flutter analyze`、全部 **59 项** `flutter test` 及 debug APK 构建通过。插件现有 Kotlin Gradle Plugin 的将来迁移提示不影响本次构建；实际 SDK 路径别名详见 Flutter 实现说明。

- 产物：`flutter_app/build/app/outputs/flutter-apk/app-debug.apk`
- 版本：`0.2.0+2`（开发调试包）
- 大小：`173337677` 字节
- SHA-256：`dabb37022d28e90eb7e0b9be784f460488b387e8477d5cb8da47c22ee97489b8`

锁定版本由 `flutter_app/pubspec.lock` 记录。UI 恢复通过 snapshot 握手同步服务；退休的旧客户端不能重新取得消息发送权，长配对不会把暂停操作排队阻塞。

## 初次固件构建（0.2.0；配对管理扩展的最终产物见后文）

ESP-IDF `5.5.4`，`espressif/led_strip 2.5.5`（`dependencies.lock`）。`tools/build_firmware.sh ble_primary` 与 `tools/build_firmware.sh legacy_udp` 均通过；使用各自 `build/<profile>/sdkconfig`，已核对两种配置的内建 Wi-Fi SSID/密码均为空。四套主机测试均通过，独立通道重定向回归确认眨眼不会重启眼球的缓动计时。

| profile | app.bin 大小 | SHA-256 |
|---|---:|---|
| ble_primary | 772272 字节 | `c27dfe497d7c36a6b8d6c60a49191a7ca1518eee7f3ff19143b332be4432b90e` |
| legacy_udp | 1049616 字节 | `5eef8f7102a190c213ab6799aaefb560853a93000fce805a11abe351ddaddad4` |

路径为固件仓库的 `build/<profile>/app.bin`；各目录同时提供 bootloader、partition table 和 `flasher_args.json`。两种应用镜像均小于现有 2 MiB factory 分区；没有移动分区。`idf.py size` 两种配置均通过：BLE 剩余 63% 应用空间，DRAM 占用 106274/321296 字节（33.08%）；legacy 剩余约 50%，DRAM 占用 122874/321296 字节（38.24%）；两者 RTC slow 均为 56/8192 字节。核对 flash 元数据只包含 bootloader、partition table、app，不包含 NVS 或板卡配置分区。

## 交付包

在两仓最终构建完成后运行 `python3 flutter_app/tool/package_ble_delivery.py`，生成 `flutter_app/build/satori-ble-a0-a1.zip` 及同名 `.manifest.json`。打包默认使用 ARM64 release APK，采用文件白名单，只含 APK、两种固件产物、协议/向量、验收与操作文档。每个文件有 SHA-256 和大小；另外记录编译源文件内容指纹，区分本次未提交实现与仓库 HEAD。NVS、真实配置、配对卡、USB 日志和开发者 sdkconfig 不进入包。


## APK 体积修正：0.2.0 历史记录（当前 0.2.1 见下文）

初次交付的 173337677 字节 debug 通用包不适合作为日常安装包，已由按 ABI 拆分的 release 包替代。构建命令为 `flutter build apk --release --split-per-abi`。启用 `packaging.jniLibs.useLegacyPackaging = true`，让直接分发的 APK 压缩原生库；Android 安装时解压，下载体积减少不等于安装占用同步减少。

| 架构 | APK 字节数 | SHA-256 |
|---|---:|---|
| arm64-v8a | 8601827 | `d5786047d70ac7ed2a7834f73366f79bd28838b71b456d4c7a0297aa3dfe4b03` |
| armeabi-v7a | 8081805 | `239fd685033d4175e7982c1d82ab5f4e29d00ac3994764b3749b14508fa1d1a2` |
| x86_64 | 8777186 | `c2279349ea5e5f60752cf447ea227657c8f9452c8af8c3a13a92817c41926b26` |

默认交付 ARM64 包 `app-arm64-v8a-release.apk`，约 **8.6 MB**，较原 debug 包减少约 **95%**；32 位 ARM 包约 8.1 MB。三个 APK 分别只包含自身架构，不再携带 debug kernel blob。APK ZIP 完整性、原生库压缩状态及 ARM64 APK v2 签名验证通过，manifest 的 `extractNativeLibs=true` 与压缩方式一致，release 未设置 debuggable。

当前 ARM64 Flutter 引擎原生库压缩后仍为 5409708 字节，应用 AOT 库压缩后为 2125820 字节，因此保持当前 Flutter 实现不能把独立 APK 压到 1–2 MB。此处仅调整构建和交付方式，没有删减 BLE 或后台功能。release 仍使用开发签名；真实手机上的 release 生命周期验证与既有硬件待验项保持待验。


## 0.2.1 历史记录：默认初次码与手机管理配对

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


### 固件验证与产物

ESP-IDF 5.5.4 的 `ble_primary`、`legacy_udp` 均构建通过，协议主本与 App 镜像校验通过。六组主机测试覆盖共同向量/session/motion、配对核心、补充配对策略、旧 UDP 解析、配置数值解析及机械映射。新增回归包含默认码拒绝换绑、前导零、窗口内改码拒绝、取消/超时/重启、主控授权与候选提交失败保留旧主控。

最终产物大小与 SHA-256：

| profile | app.bin 字节数 | SHA-256 |
|---|---:|---|
| ble_primary | 779968 | `304b9018472b09b68fbc84ab3379da60ea739c0feab12b24af0f2126326e068f` |
| legacy_udp | 1049616 | `c3db7ee34e4f4e93792ec44b64be100b94787cac7dc7db11353217f9f4cbdd49` |

`idf.py size`：BLE DRAM 106338 字节（33.1%），legacy DRAM 122874 字节（38.24%）；两应用仍适配原有2 MiB分区，剩余约63%/50%。固件的内建SSID/密码均为空，flash元数据只写0x0/0x8000/0x10000，不含NVS和板卡配置。

启动时在 NimBLE store 初始化完成后检查 bond 和身份；会话临界区不包含可阻塞的配对互斥锁。旧手机提前断线会清除其500ms断开任务，避免该任务影响后续新连接。配对窗口超时拒绝迟到的SMP候选，host重置关闭窗口。

异常恢复限制：成功换绑后如果底层旧bond删除失败，新主控仍是唯一被授权的手机，但残留bond可能占满两条存储槽，阻止下一次换绑；重启会按已持久化的新主控清理残留bond，若存储持续故障则需USB维护。真实NVS断电/故障注入及无线时序仍属于硬件待验范围。


## 0.2.2：多手机轮流连接、连接自动启用输出

用户修改了原来的单主控和连接暂停策略：多个手机可使用同一码完成配对，最多8台保存bond，同一时间只允许一台连接。已连接时停止可连接广播，断开或连接失败后恢复；不能抢占。空闲时允许使用当前配对码的新手机加入，满额拒绝且不自动驱逐。所有已绑定手机可改码，已有bond不因改码或升级失效。新模式隐藏换绑按钮，旧固件兼容入口仍保留；逐台删除bond尚未提供无线入口，USB可维护清理。

每次新连接或重连完成认证/订阅/CLAIM后，加载按设备身份保存的维护范围或内置默认，再自动ARM并读取快照初始化目标。普通用户无需配置范围或启动值；显式设备配置损坏/非法时保持连接并显示NOT_CONFIGURED。显式暂停取消本次待启动，下一次重新连接仍会自动启用。旧预设、自动行为和积压目标不回放。此行为按用户最新指令实现，取代原计划的“重连停在暂停态”。

协议minor2、security_policy2、能力bit8表达多bond模式；SET_PAIRING_CODE仍为opcode8；旧换绑opcode9/10在新模式返回BAD_OPCODE且没有副作用。两端同步保留原golden与v1.1历史向量，新增v1.2能力读取、拒绝及共享配对场景。


### 内置默认与隐藏维护参数

用户追加要求取消必填配置。内置profile `satori_c3_v1`采用Qt生产源`SatoriManagerContent/mobileclient.h:35`的500–2500三通道逻辑范围，以及`mobileclient.cpp:27`的初始[1500,1500,1500]。这些值来自原产品代码，不是从fake测试姿态推定的实测结果。逻辑中心映射为[90,90,90]角输入，CH3/CH2耦合仍执行；实际输出继续应用板卡配置的scale/offset/zero/reverse与角度clamp。现有GPIO与机械标定覆盖保留。

App缺少收藏范围时回退内置范围，自定义字段收起到“高级维护”；固件没有维护启动覆盖时回退内置姿态，合法显式覆盖优先，损坏/非法配置仍拒绝。上电无PWM，认证连接后才由App自动ARM。未烧录硬件，当前装配的实际运动/行程仍待验证，不将内置默认标记为实测安全。


### 0.2.2 App 最终验证与产物

Flutter格式检查33个文件无变化，`flutter analyze`无问题，全部 **94项测试通过**。覆盖多手机同码配对、改码保留bond、8台上限、连接互斥、无配置自动使用内置范围、连接及重连自动ARM、无旧动作回放、暂停取消排队ARM、自动ARM期间断线、配置异常、隐藏维护表单与旧固件UI兼容。`flutter build apk --release --split-per-abi`通过。

| 架构 | APK 字节数 | SHA-256 |
|---|---:|---|
| ARM64 | 8682119 | `5bcde9076c1b8911e435410e1e312c691ae98cf21061370e62f65659630f30bf` |
| ARM32 | 8167093 | `4528b5adb5ca0e036507bc335f0236e94c9113d2fa58bd7d534d5840af51733b` |
| x86_64 | 8858646 | `ea1cc9a2b8c86e1cdf233bcfc5e49b29b822970337041437311cb62bd4964ccd` |

App版本0.2.2+4；ARM64 APK v2签名验证通过，仍为现有开发签名。按ABI交付并压缩原生库，未删减BLE/后台功能。真机多手机轮流使用、配对存储故障、真实运动及Android生命周期尚未验收，本次无烧录。


### 0.2.2 固件最终验证与产物

ESP-IDF 5.5.4 下BLE与legacy两种profile构建及`idf.py size`通过。**7组主机测试通过**：协议/session/motion、配对核心、配对策略、legacy目标解析、配置解析、机械映射、内置startup profile。覆盖8个bond无驱逐、已绑定手机改码、共享模式拒绝旧换绑操作、合法维护覆盖优先、非法/部分配置拒绝及内置逻辑启动映射。NimBLE集成完成静态复核；存储写失败闩锁及真实无线/断电故障仍待硬件验证。

| profile | app.bin 字节数 | SHA-256 |
|---|---:|---|
| ble_primary | 777168 | `9a38fb5a5dcd6dedfe61b8da53a5d86201d17d7b6aa2cdb1628221672d2394a3` |
| legacy_udp | 1050176 | `b0a8465eaaab57cbb5f0db174dd098cd220843236beb76d3ccd4b2175eb36d71` |

BLE实际生成配置MAX_BONDS=8、MAX_CONNECTIONS=1；DRAM106362字节（33.1%），FlashCode579250字节，应用分区剩余约63%。legacy DRAM122874字节（38.24%），FlashCode816380字节，应用分区剩余约50%。内建Wi-Fi SSID/密码为空；flash元数据仍只写bootloader、partition table和app，保留NVS/config分区。

当前peer须出现在NimBLE保存的bond列表中并通过认证。由于SDK在持久化前先更新RAM，生产代码另包装store_write_cb记录密钥写入失败；失败后暂停会话并拒绝授权直到设备重启，避免将仅存在于RAM的记录当作成功保存。没有通过测试输出虚假的物理位置或电量，未烧录或运行硬件动作。


## PR 审查修复：重连暂停意图与 RELEASE 确认窗口

审查基线：App ffe02b5、固件 f954f27。P1修复将自动启动意图绑定到整轮断线恢复；退避等待、首次连接失败和后续重试不会重新取得被暂停撤销的ARM许可。普通未暂停的重连仍自动ARM，旧动作不回放。

P2将RELEASE同帧确认窗口固定为3000 ms，从控制任务实际完成释放开始计时；对应客户端500 ms×4次尝试、另加1000 ms余量。释放完成即撤销token及插值，延长窗口不恢复控制权，重复请求不延长截止时间。App fake同步，并停止释放期间状态轮询、忽略已在途轮询的零token，避免其提前断开等待重试的链路。共同协议与向量时序字段同步。

CI与本地验证分开记录：审查时App ffe02b5的GitHub Actions已成功，但执行的是格式、analyze、测试及debug APK；固件f954f27当时没有Actions运行/check-run。跨仓协议检查、三ABI release与固件主机/双配置构建的既有记录属于本地验证。CI扩展建议保留为后续，本轮保持上述最小修复范围。真机待验项目不因源码审查或本地测试变为通过。

### 本轮 App 本地复验

格式检查33文件、flutter analyze、全部98项测试、协议哈希检查及三ABI release构建通过。新增P1两条重连暂停回归；P2保持默认500 ms超时，分别丢1/3条RELEASE确认，模拟80 ms写入处理与60 ms通知延迟，并覆盖已在途状态轮询返回撤销token。正常释放仍在收到确认后立即断开，不等待3秒。

| ABI | APK字节数 | SHA-256 |
|---|---:|---|
| arm64-v8a | 8682319 | `c7ed85908fd551c6b2464c97560b211d4c554242eeb69d1d59f4f1c5153b7154` |
| armeabi-v7a | 8167297 | `e0083ea96bff67976a4478eaa04853894348eb2ca79a112a25e2162941d65e6d` |
| x86_64 | 8858794 | `83a1bc9648eec6ab09dbcbe2a96f0e084bdd71e95d2a59cf6589108bff4ed52d` |


### 本轮固件本地复验

7组主机测试、ESP-IDF 5.5.4的BLE/legacy构建及size检查均通过。RELEASE回归覆盖受理后延迟完成、完成后500/1500/2999 ms缓存重放、3000 ms到期拒绝与断链、重复不续窗、拒绝CLAIM/旧缓存/SET_TARGET、不恢复token/运动以及uint32时钟回绕。v1.2 timing向量由两端测试消费。

| profile | app.bin 字节数 | SHA-256 |
|---|---:|---|
| ble_primary | 777440 | `3dc07d171b9aeab5a80ab0b8b79bae25e11ee889ed9644351b8529ed72a0aad0` |
| legacy_udp | 1050176 | `7618d93cd0558b141b7e71f6e83e4e6497453178128e74c7bf3657c57fa2779b` |

BLE DRAM106362字节（33.1%）、FlashCode579512、应用分区余63%；legacy DRAM122874字节（38.24%）、FlashCode816380、余50%。App ARM64 APK v2验签通过（开发签名）。未烧录，硬件待验项保持不变。
