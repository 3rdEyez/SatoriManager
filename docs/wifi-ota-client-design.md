# 限时浏览器 OTA 与离线包预检

当前阶段只完成纯内存 package 预检及本地设计：没有接入 App UI、BLE 新协议、文件选择器、网络、Android 权限或服务，没有生成正式密钥、刷入签名 seed 或在设备开网。双槽/回滚基础不等于已完成无线升级。

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
