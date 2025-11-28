# SatoriManager

跨平台机器人眼部控制客户端，使用 React Native 构建，支持 Android 和 iOS。

## 项目简介

SatoriManager 是一个移动端远程控制应用，用于操控 SatoriEye 机器人眼部运动。支持 **WiFi (UDP)** 和 **蓝牙 (BLE)** 双连接方式，提供模式切换、摇杆控制、预设动作播放等功能。

## 技术栈

| 技术 | 用途 |
|------|------|
| **React Native 0.76** | 跨平台移动应用框架 |
| **TypeScript** | 类型安全的 JavaScript |
| **Zustand** | 轻量级状态管理 |
| **react-native-ble-plx** | 蓝牙低功耗 (BLE) 通信 |
| **react-native-udp** | UDP 网络通信 |
| **react-native-gesture-handler** | 手势处理 |
| **react-native-reanimated** | 流畅动画 |

## 系统要求

- **Node.js** >= 18
- **pnpm** (包管理器)
- **Android Studio** (Android 开发)
- **Xcode** (iOS 开发，仅 macOS)
- **JDK 17** (Android 编译)

## 快速开始

### 一键初始化

**Windows (PowerShell):**
```powershell
.\init.ps1
```

**Linux/Mac:**
```bash
chmod +x init.sh && ./init.sh
```

### 手动安装

```bash
# 安装依赖
pnpm install

# 启动 Metro 开发服务器
pnpm start

# 运行 Android
pnpm android

# 运行 iOS (仅 macOS)
pnpm ios
```

## 功能特性

### 连接方式

| 方式 | 特点 | 适用场景 |
|------|------|---------|
| **WiFi (UDP)** | 广播自动发现，低延迟 | 室内局域网 |
| **蓝牙 (BLE)** | 点对点连接，便携性强 | 户外/无网络环境 |

### 控制模式

- **自动模式**: 机器人自动运动，支持随机眼球运动
- **手动模式**: 通过摇杆精确控制眼球位置
- **睡眠模式**: 低功耗待机状态
- **人脸识别模式**: 自动追踪人脸 (预留)

### 主要页面

1. **主控制页面**
   - 模式切换按钮
   - 摇杆控制 + 电量显示
   - 预设动作播放
   - 连接状态指示

2. **眼部控制页面**
   - 眼皮角度拨盘
   - 瞳孔大小拨盘 (预留)

3. **设置页面**
   - PWM 变化范围调节
   - 更新间隔设置
   - 自动复位开关
   - 自动眨眼开关

## 蓝牙架构 (Blue-Eye Architecture)

### 系统拓扑

```
┌─────────────────────────────────────────┐
│         React Native App (Central)       │
├──────────────┬──────────────┬───────────┤
│   UI Layer   │ Protocol Layer│ BLE Driver│
│  (Joystick)  │(Buffer Encode)│ (ble-plx) │
└──────┬───────┴──────┬───────┴─────┬─────┘
       │              │             │
       │    Encoded Buffer         │
       │              ▼             │
       │     ┌────────────────┐    │
       │     │ BLE Write (NR) │────┼──────────┐
       │     └────────────────┘    │          │
       │                           │          ▼
       │                    ┌──────┴──────────────────┐
       │                    │   ESP32-S3 (Peripheral)  │
       │                    ├──────────────┬──────────┤
       │                    │  BLE Server  │ Parser   │
       │                    │    Stack     │  (C++)   │
       │                    └──────┬───────┴────┬─────┘
       │                           │            │
       │    ┌──────────────────────┘            │
       │    │ BLE Notify                        ▼
       │    ▼                           ┌─────────────┐
       └────────────────────────────────│   Actuator  │
                                        │Servo/Power  │
                                        └─────────────┘
```

### GATT 服务定义

| 实体 | UUID | 属性 | 用途 |
|------|------|------|------|
| Primary Service | `6e400001-b5a3-f393-e0a9-e50e24dcca9e` | - | Nordic UART Service |
| TX Characteristic | `6e400002-b5a3-f393-e0a9-e50e24dcca9e` | WriteWithoutResponse | 手机 → 眼球 |
| RX Characteristic | `6e400003-b5a3-f393-e0a9-e50e24dcca9e` | Notify | 眼球 → 手机 |

### 通信协议

#### 上行指令 (App → ESP32)

固定 6 字节，小端序:

```
[Header][CMD][Data1][Data2][Data3][Checksum]
  0xA5   XX    XX     XX     XX      XOR
```

| CMD | 功能 | Payload |
|-----|------|---------|
| 0x01 | 摇杆控制 | X角度, Y角度, 保留 |
| 0x02-04 | PID参数 | 高字节, 低字节, 保留 |
| 0x05 | 模式切换 | 模式值, 0, 0 |
| 0xFF | 心跳 | 0, 0, 0 |

#### 下行遥测 (ESP32 → App)

固定 8 字节:
```
[Header][Type][Val1][Val2][Val3][Val4][Status][Checksum]
```

## 报文格式 (UDP)

| 报文类型 | 格式 | 说明 |
|---------|------|------|
| 发现请求 | `SatoriEye_DISCOVERY_REQUEST` | 客户端广播寻找设备 |
| 发现响应 | `SatoriEye_DISCOVERY_RESPONSE,<电量>` | 服务器响应 |
| 心跳请求 | `SatoriEye_HEARTBEAT_REQUEST` | 保持连接 |
| 心跳响应 | `SatoriEye_HEARTBEAT_RESPONSE,<电量>` | 确认在线 |
| 模式设置 | `SET_MODE:<模式>` | 切换工作模式 |
| PWM控制 | `CH1:<值>CH2:<值>CH3:<值>` | 直接PWM控制 |
| 平滑PWM | `SMOOTH:CH1:<值>CH2:<值>CH3:<值>MS:<时长>` | 渐变控制 |

## 预设动作

存储在 `PresetActions.json`:

```json
{
  "wink": [
    { "CH1": -1, "CH2": -1, "CH3": 0.0, "duration": 200 },
    { "CH1": -1, "CH2": -1, "CH3": 1.0, "duration": 200 }
  ]
}
```

- `-1`: 保持当前值不变
- `0-1`: PWM 比例值

## 开发命令

```bash
# 运行测试
pnpm test

# 监听模式测试
pnpm test:watch

# 测试覆盖率
pnpm test:coverage

# 类型检查
pnpm typecheck

# 代码检查
pnpm lint
```

## 项目结构

```
SatoriManager/
├── App.tsx                     # 应用入口
├── src/
│   ├── types/                  # TypeScript 类型定义
│   ├── services/
│   │   ├── MobileClient.ts     # UDP 通信服务
│   │   ├── BluetoothClient.ts  # 蓝牙通信服务
│   │   └── ConnectionManager.ts # 统一连接管理器
│   ├── store/
│   │   └── appStore.ts         # Zustand 状态管理
│   ├── components/
│   │   ├── Joystick.tsx        # 摇杆组件
│   │   ├── Dial.tsx            # 拨盘组件
│   │   ├── StyledButton.tsx    # 按钮组件
│   │   └── ConnectionModal.tsx # 连接选择弹窗
│   └── screens/
│       ├── MainScreen.tsx      # 主控制页面
│       ├── ControlScreen.tsx   # 眼部控制页面
│       └── SettingScreen.tsx   # 设置页面
├── __tests__/                  # 测试文件
├── android/                    # Android 原生代码
└── ios/                        # iOS 原生代码
```

## 常见问题

### Q: 无法连接到设备?

1. **WiFi**: 确保手机和设备在同一局域网
2. **蓝牙**: 检查蓝牙权限是否已授予
3. 确认设备已开启并处于可发现状态

### Q: 蓝牙扫描不到设备?

- Android 12+ 需要 `BLUETOOTH_SCAN` 和 `BLUETOOTH_CONNECT` 权限
- 确保设备名称以 `SatoriEye` 开头

### Q: 控制延迟较高?

- 蓝牙模式使用 `WriteWithoutResponse` 以降低延迟
- 摇杆发送频率限制为 30Hz 以防止蓝牙栈溢出

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

GPL License

## 联系方式

- **GitHub**: [@AkazaAkali](https://github.com/AkazaAkali)
- **Bilibili**: [space.bilibili.com/381473156](https://space.bilibili.com/381473156)
