# 觉瞳真机验证记录

## 2026-09-29：串口诊断

- Ciallo 通过 USB 识别觉瞳为 Espressif USB JTAG/serial debug unit，创建 `/dev/ttyACM0`。在该主机上端口能保持连接。
- 通过 `sg dialout` 以只读方式打开串口约 20 秒，采集到两条 `UDP_SERVER: recvfrom failed: errno 11` 日志。采集期间端口未断开。没有发送串口命令、PWM、动作或固件写入。
- 旧有入网方式使用 Ciallo 上的 `~/下载/设置Wifi/` 烧录工程。只读检查表明 `config.ini` 包含 Wi-Fi 参数及舵机校准项；其 SSID 与 Ciallo、Satori 当前连接的 Wi-Fi 不同。诊断时未输出或记录密码，也未运行原 Windows 烧录工具。
- 现有 `full_flash.bin` 的分区表包含独立 `config` 分区（偏移 `0x300000`、大小 `0x2800`）。
- Satori 主机上同一设备曾短暂枚举，随后断开，并出现 USB 描述符读取错误 `-71`。这不能单独定位为线缆、主机接口、供电或固件原因；后续串口诊断优先在 Ciallo 进行。
- 当时的串口日志仅说明固件运行到了 UDP 服务相关代码，不能单独证明 Wi-Fi 或物理动作。

## 2026-09-29：Wi-Fi 配置写入与 UDP 验证

- Satori 无线扫描确认目标 2.4 GHz SSID 在 2412/2462 MHz 广播。ESP32-C3 只支持 2.4 GHz；候选配置采用与当前 5 GHz SSID 同名、去掉 `-5G` 后缀的 2.4 GHz 名称。SSID 大小写经现有配置与现场扫描核对。密码未输出或记录到仓库。
- Ciallo 上通过 `/dev/ttyACM0` 将设备当前 `config` 分区完整备份至 `~/下载/设置Wifi/backup-config-before-stage-a-20260929.bin`（10240 字节，权限 0600）。写入前再次回读首扇区，逐字节与备份一致。
- 以设备自身备份为基础，仅替换 `ESP_WIFI_SSID`、`ESP_WIFI_PASSWORD` 两行；其他配置行、舵机校准、UDP 8888 与后续扇区均保持原值。用 esptool v5.4.0 仅擦写 `0x300000` 至 `0x300fff` 的 4096 字节，写入哈希校验通过。随后回读完整 `config` 分区至 `~/下载/设置Wifi/verify-config-after-stage-a-20260929.bin`，与候选分区逐字节一致，并通过看门狗重启设备。
- 重启后设备以 MAC `98:3d:ae:b5:d7:20` 出现在局域网 `192.168.1.17`，ICMP 2/2 成功。从 Satori 向该地址 UDP 8888 发送三次 `SatoriEye_DISCOVERY_REQUEST`，均从同一设备收到 `SatoriEye_DISCOVERY_RESPONSE,50`（接收端口 8889）。定向广播 `192.168.1.255` 曾收到回应；全局广播 `255.255.255.255` 本轮未收到回应，需在手机上核对自动发现，必要时在客户端输入设备 IP 发现。
- 真机对 `SatoriEye_HEARTBEAT_REQUEST` 返回完全相同的报文，而非当前客户端预期的 `SatoriEye_HEARTBEAT_RESPONSE`。这是待固件重构后复测的协议差异；当前 Flutter 客户端不会将该回显计作会话响应，因此真机连接可能在 60 秒后被判定失联。
- 没有发送 PWM 或动作报文。Android 手机尚未准备好；真实控制、摇杆、回中、自动动作、通知停止、进程生命周期和锁屏 30 分钟/2 小时仍待验证。

## 下一步

固件工程 `/home/kyle/projects/ESP-3RDEYE` 已在提交 `f7589cd` 构建出 ESP-IDF
v5.5.4 应用镜像，并复制到 Ciallo。新镜像会返回独立心跳响应，移除虚构电量和
串口配置值日志。**截至本记录，新镜像尚未烧录**：Ciallo 的 ESP32-C3 原生 USB
串口在应用分区备份期间出现描述符错误 `-71`，`/dev/ttyACM0` 消失；现场应用
分区只读出首个 64 KiB。设备仍可通过 Wi-Fi 访问，运行的仍是旧固件。完整回退
备份与稳定的串口恢复后，按固件仓库 `FLASHING.md` 继续。

1. 让 Android 手机与觉瞳处于可达网络，安装本工程构建的 APK。若广播发现无结果，在客户端输入 `192.168.1.17` 定向发现；该地址可能随 DHCP 变化。
2. 真实设备模式下先填写已确认的三通道安全范围和初始目标，再验证电量、心跳与连接恢复。
3. 在现场观察机构时，小幅验证 CH1/CH2 摇杆、松手回中及 CH3 保持；记录实际动作和接收证据。
4. 继续按 [README](README.md) 中的待验证项检查停止、断开、通知入口和锁屏 30 分钟/2 小时。
