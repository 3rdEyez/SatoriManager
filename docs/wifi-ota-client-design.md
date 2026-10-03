# 局域网配网维护与浏览器 OTA

App 0.2.7+9 已接入设置页升级入口、独立认证 BLE 扩展、状态确认和退出流程；内存 package 预检仍不验签或传输。没有添加文件选择器、App Wi-Fi 绑定、新 Android 权限或服务，没有生成正式密钥、刷入签名 seed 或在设备开网。本地闭环模拟不等于无线部署完成。

## 简化操作路径（实现/部署边界）

用户通过已有授权设备上的显式 BLE 请求主动开启限时维护窗口。窗口内设备临时 SoftAP；上传者手动进入 Wi-Fi 设置连接设备，然后用任意设备的浏览器选择并上传包。上传客户端无需 BLE 配对，也不要求 BLE 在上传期间不断线。BLE 开窗控制与浏览器上传授权/验签是不同环节；既有运动租约不得借维护窗口重新 ARM 或补播旧动作。

任意浏览器可上传不代表任意固件可安装：只有批准密钥签出的完整镜像通过设备原生验证后才可选为启动槽。窗口超时、取消、上传中断和失败的具体关闭/清理策略由固件维护状态机实现；本文件不启动服务。未批准的安全配置、信任根及实际部署仍需完成后再接入。

## IDF 原生签名信任链

候选采用 ESP-IDF 5.5.4 C3 原生 Secure Boot v2 RSA3072/RSA-PSS 镜像格式，并使用 signed-app verification without hardware Secure Boot。签名块位于实际 .bin 尾部，不在 JSON 中自创签名/公钥字段。IDF 取当前运行应用第一签名块公钥验证新镜像，因此必须先经受控 USB 安装已签名的初始 seed；当前未签名 0.2.4 不能直接充当信任起点。只使用首个签名块，不采用多 key 方案。

此模式不等于启用硬件 Secure Boot，也不抵御可直接改写 flash 的攻击者；不允许据此烧 eFuse、启用 Flash Encryption 或修改 ROM 恢复权限。正式密钥与 seed 构建/安装尚未完成，本 App 预检不具备实际 RSA 验签能力。[ESP-IDF 5.5.4 官方说明](https://docs.espressif.com/projects/esp-idf/en/v5.5.4/esp32c3/security/secure-boot-v2.html#signed-app-verification-without-hardware-secure-boot)

## 候选 .sota 容器与接口

容器：4 字节 little-endian 无符号 manifest JSON 字节长度（1..1024），随后严格 UTF-8 JSON，最后完整原始 .bin。长度必须精确相符，不接受尾随数据；不使用 ZIP、路径提取或 base64 镜像。`image_length` 包含镜像填充及签名块，最大 1507328 字节；SHA256 声明对应全部 .bin 字节，不是容器、JSON 或 IDF 签名块内的局部 image digest。

schema 1 严格只有下列字段，未知、缺失及旧 signature/key_id 字段拒绝：

```json
{
  "schema": 1,
  "board": "satori_c3_v1",
  "chip": "esp32c3",
  "image_length": 798448,
  "sha256": "<64 lowercase hex characters>",
  "version": "0.2.4",
  "image_format": "esp-idf-sbv2-rsa3072"
}
```

示例长度仅用于结构说明，不证明该版本已签名。版本严格为无前导零的 major.minor.patch，每段十进制 0..65535；不接受后缀、空白或 CRLF 注入。manifest 本身并未签名；设备将来还必须核实际 ESP app 描述与声明，真正的来源认证以原生镜像签名为准。

`OtaPackageManifest.fromJson` 检查声明；`declaredSha256` 解码不可变的 32 字节；`OtaPackageContainer.decode` 解码内存容器并交出不可变镜像副本；`OtaPackagePreflight.inspect` 校验实际长度。均不读真实文件、计算摘要、解析签名块或验签。结果始终 `mayTransfer=false`、`signatureVerified=false`、`authenticityEstablished=false`。默认阻止原因为无批准信任策略；即便调用者声明策略存在，也因没有真实验签而阻止。不能把格式声明或 hash 当作可信来源证明。

## Android 可选集成（不是默认路径）

未来如集成 App，API29+ `WifiNetworkSpecifier` 可以请求局域网连接，首次通常需系统对话授权；它不提供互联网，secondary STA 要求设备支持和 target API31+，无法保证保留原 Wi-Fi 或跨 OEM 一致。失败、拒绝、取消须处理并释放 callback。[网络请求指南](https://developer.android.com/develop/connectivity/wifi/wifi-bootstrap)、[WifiNetworkSpecifier API](https://developer.android.com/reference/android/net/wifi/WifiNetworkSpecifier)

App 传输若集成，应通过专用 `Network.openConnection`/socketFactory 绑定请求；不把整个进程绑到维护网络。网络路由不替代信任验证，也不保证 BLE/Wi-Fi 射频共存稳定。[Network API](https://developer.android.com/reference/android/net/Network)

Android13+ 管理 Wi-Fi 需评估 `NEARBY_WIFI_DEVICES` runtime permission 和 `neverForLocation`；旧版可能需 fine location，扫描类 API 有额外位置要求。还应逐 API 确认 INTERNET/网络状态/更改网络/Wi-Fi 权限，本轮未添加。附近设备权限与 BLE 同组，撤销后须处理。[Wi-Fi 权限指南](https://developer.android.com/develop/connectivity/wifi/wifi-permissions)

同手机开热点并连设备 AP 依赖 STA/AP 硬件与 OEM 并发支持，不能作普遍替代路径；路由和同频吞吐须实测。[AOSP 并发说明](https://source.android.com/docs/core/connect/wifi-sta-ap-concurrency)

未来本地选包推荐 SAF `ACTION_OPEN_DOCUMENT` + `CATEGORY_OPENABLE` 单文件 URI，不申请全部存储访问；限制读取长度、暂存 App 私有目录。SAF 可含云提供者，纯离线要选择已下载文件并处理 URI 不可读。[SAF 官方指南](https://developer.android.com/training/data-storage/shared/documents-files)

## 本地验证与后续边界

八项测试涵盖摘要声明、无验签阻止、错误目标/格式/旧字段、槽与文件长度边界、版本/注入、长度前缀容器、畸形 UTF-8/JSON、截断/尾随数据、不可变副本。这不代表签名真实性或真实 OTA 测试。后续需验正确/错误 RSA key、签名损坏/无签名、seed 信任链、错误 app 描述、窗口中断/超时、浏览器/OEM 行为及回滚；设备与正式密钥动作另按批准范围执行。

## App 开窗与退出闭环

设置页区分旧固件不支持、扩展存在但签名升级未就绪、真实开窗连接资料和未知状态。开启之前撤销自动动作和自动 ARM 意图，等待既有 HALT 确认。独立 UUID `4d89f6a0-73b9-4f14-9d3e-63b2145a0007` 为 encrypted/authenticated READ+WRITE；不改 DeviceInfo 能力或 Control v1.2。命令与控制写共用串行队列；维护中清本机 CLAIM，停旧心跳/控制状态轮询。

请求10字节：v1/action(open1,close2)/requestId LE32/windowId LE32。requestId非零；open windowId=0；close windowId非零且匹配当前窗口。状态18字节头+SSID/password ASCII：v1、state0..6、result0..6、reserved0、ACK requestId LE32、windowId LE32、remainingMs LE32、SSID长度、密码长度。SSID≤32、密码≤64。state closed0/opening1/open2/uploading3/closing4/committed5/failed6；result ok0/busy1/signing-not-ready2/invalid3/not-ready4/stale-window5/internal6。

写成功不算ACK。App仅匹配requestId/result0/目标最终状态才确认命令；丢失回执同id同字节有界重试，不新开/延长窗口。剩余时限来自设备读回，不凭本机倒计时宣称关闭。committed只称镜像已提交/待重启验证，不能取消冒充撤销或称升级完成。临时SSID/password仅有效UI状态使用，不日志/持久化；读取失败或掉线清除。

开窗首次await之前锁住自动恢复，也覆盖HALT中途掉线。维护断线不自动连接/ARM；用户可点“重新连接确认窗口状态”。认证连接先读维护状态，已有窗口跳过CLAIM/ARM，仅管理窗口；浏览器上传不依赖此连接。Closed真实确认后可“退出升级并重新连接”：断开、fresh CLAIM、保持暂停。禁自动ARM意图跨后续断线保留，直到用户明确启用控制成功；普通拍摄原有断线恢复规则保留。

当前固件版本来自fresh DeviceInfo，未获得目标版本和启动验证不声称升级成功。可变长度BLE长读与OEM实机行为尚未测，部署时需验证。新增维护测试覆盖HALT断线、旧固件/未ready、丢ACK与超时、重复请求、迟到状态、提交拒取消、断线和freshCLAIM退出；UI测试覆盖连接资料与未知状态恢复入口。它们不代表设备网络或正式签名测试。

## LAN 主路径（本地实现，部署仍需实测）

设置页优先“连接网络并开启维护”：用户每窗输入 2.4GHz WPA2 个人网络 SSID 和密码，密码遮蔽显示、关闭输入法学习、提交即清空输入框。配置仅传入设备本次维护 RAM，不保存手机偏好或设备持久存储，结束清除；没有保存选项、扫描或自动复用旧凭据。电脑保留原网络，与设备同局域网，直接打开 BLE 实读的 IPv4 地址；页面填写窗口令牌，上传完整签名 .sota 包。隔离网络/访客网络可能无法访问，备用 AP 入口仍需明确开启。沿用旧 IP 直连概念，不恢复 UDP 控制或承诺发现扫描。

独立认证 read/write UUID `4d89f6a0-73b9-4f14-9d3e-63b2145a0008`，不修改旧 DeviceInfo、Control v1.2 或能力位；缺少扩展时明确不支持并不发送配置。命令12字节头：schema1/action(openLAN1,close2)、requestId LE32、windowId LE32、SSID长度、密码长度，后接 UTF-8 SSID1..32字节及ASCII密码8..63字节。open windowId0；close非零当前windowId、两个长度0。拒绝open/WEP/64位hex密码。本地Android写前请求MTU256，未满足整个命令长度则停止，不分段冒充原子配置。

状态24字节头：schema/state/result/detail、ACK requestId LE32、windowId LE32、remainingMs LE32、IPv4四个网络序字节、token长度、3个零reserved，后接令牌。state/result与AP相同；detail none0/invalid-config1/connect-timeout2/wifi-error3/lost-link4。仅Open/Uploading携带32位lowerhex令牌；连接中、失败及关闭不携带。Ready须真实设备Open、有效IP/windowId/令牌；写入或连接中不算联网。窗口120秒包含最多20秒连接阶段。open/close设备确认等待26秒，客户端45秒；连接中关闭可能等待有界连接结束，只有真实Closed才能退出。

电脑地址不含令牌；上传使用 `X-Satori-Window` header。令牌不进入公共snapshot、偏好、日志或异常，仅匹配客户端和当前窗口的私有RAM响应/UI使用，断线/窗口变化清除。两个维护路径互斥，另一窗口活动或状态未知时不允许切路径，防止APClosed掩盖LAN仍开启。真实Closed后freshCLAIM仍暂停，不自动ARM。

本地模拟覆盖配置字节界限、畸形状态、旧固件、真实Ready/连接失败、MTU拒绝、两路径互斥、凭据快照隔离和暂停退出。未进行真实BLE长写/读、局域网连通、浏览器上传或正式签名部署；本轮未新增Android权限、插件或网络服务。
