# SatoriManager 项目

## 项目简介
SatoriManager 是一个基于 Qt 和 QML 的小型机器人控制项目。通过此应用，用户可以在移动端远程操控机器人，支持模式切换（如自动模式、睡眠模式、人脸识别等）以及机器人头部的旋转和眨眼控制。此项目主要包含移动端控制客户端和机器人服务器端的通讯。

## 功能特性
- **自动模式**、**睡眠模式**、**人脸识别**等模式切换
- 控制机器人上下左右旋转及眨眼
- 自动寻找并连接到机器人服务器
- 心跳检测与重连机制，确保稳定的连接
- 本地模式更新后对应按钮高亮提示

## 技术栈
- **C++ & Qt**：用于实现移动客户端和与机器人服务器的通信
- **QML**：负责 UI 界面设计，提供直观的操控体验
- **UDP**：用于实现客户端与服务器之间的实时通信

## 系统要求
- **Qt** 6.2 或更高版本
- **C++17** 或更高版本
- 支持 **UDP** 的网络环境

## 安装与使用

### 克隆项目
```bash
git clone https://github.com/你的仓库地址/SatoriManager.git
cd SatoriManager
```

### 编译项目
1. 使用 Qt Creator 或者命令行进入项目根目录。
2. 配置 Qt Kit，选择适合你的目标平台（例如 Android 或 Desktop）。
3. 编译并运行项目。

### 项目配置
确保服务器和客户端处于同一局域网，以便能够自动发现服务器。

### 项目目录结构
```
SatoriManager/
├── src/                     # 源代码文件
│   ├── MobileClient.h       # 客户端核心类定义
│   ├── MobileClient.cpp     # 客户端核心类实现
│   ├── main.cpp             # 程序入口
│   └── ...                  # 其他源代码文件
├── qml/                     # QML UI 文件
│   ├── main.qml             # 主界面
│   └── ...                  # 其他 UI 相关文件
├── resources/               # 资源文件（图标、图片等）
└── README.md                # 项目说明文件
```


## 使用说明

### 模式切换
通过 UI 中的模式按钮可以切换不同的工作模式。切换模式后，按钮会高亮显示当前模式。
- **自动模式**：机器人进入自动导航模式。
- **睡眠模式**：机器人进入低功耗模式。
- **人脸识别**：机器人将激活人脸识别功能。

### 控制机器人旋转与眨眼
UI 界面中提供了控制机器人头部的按钮，用户可以控制机器人向上、向下、向左和向右旋转，以及眨眼动作。每个按钮会发送相应的指令到服务器，服务器响应后执行相应操作。

### 连接与重连
初次连接时，客户端会自动广播发现消息，寻找局域网内的机器人服务器。若服务器响应，将自动连接并保持心跳检测。若出现网络中断，客户端将自动重连。
以下是 README 中有关 UDP 数据格式要求的部分描述，用于明确客户端与机器人服务器之间的通信协议格式，确保传输信息的一致性和解析的准确性：



## UDP 数据格式要求

本项目采用 UDP 协议进行客户端与机器人服务器之间的通信，以下是数据格式的具体要求：

### 通用数据格式

每个消息包均为 UTF-8 编码的字符串，格式为 `COMMAND:参数1:参数2`。例如：
- **设置模式**：`SET_MODE:Auto`
- **移动控制**：`MANUAL:MOVE_UP`

### 数据包类型和格式

1. **发现请求**
   - **发送方**: 客户端
   - **格式**: `"SatoriEye_DISCOVERY_REQUEST"`
   - **说明**: 发送广播以发现局域网内的机器人服务器。

2. **IP 广播**
   - **发送方**: 服务器
   - **格式**: `"SatoriEye_IP:<ip_address>:<port>"`
   - **说明**: 机器人服务器响应发现请求，广播其 IP 和端口。例如，`"SatoriEye_IP:192.168.1.100:8888"`。

3. **心跳包**
   - **请求**：
     - **发送方**: 客户端
     - **格式**: `"SatoriEye_HEARTBEAT_REQUEST"`
     - **说明**: 客户端定期发送心跳请求，确保连接有效。
   - **响应**：
     - **发送方**: 服务器
     - **格式**: `"SatoriEye_HEARTBEAT_RESPONSE"`
     - **说明**: 服务器回复心跳包，客户端重置超时计数。

4. **模式设置**
   - **发送方**: 客户端
   - **格式**: `"SET_MODE:<ModeName>"`
   - **说明**: 客户端请求服务器进入指定模式，`<ModeName>` 可为 `Unconnected`、`Auto`、`Manual`、`Sleep` 或 `FacialRecognition`。
   - **示例**: `"SET_MODE:Auto"`

5. **模式设置响应**
   - **发送方**: 服务器
   - **格式**: `"SET_MODE_SUCCESS:<ModeName>"`
   - **说明**: 服务器确认模式变更成功，通知客户端新的模式状态。

6. **机器人控制命令**
   - **发送方**: 客户端
   - **格式**: `"MANUAL:<Command>"`
   - **说明**: 手动控制命令，用于在手动模式下控制机器人移动。
   - **有效命令**:
     - `LOOK_UP` - 向上看
     - `LOOK_DOWN` - 向下看
     - `LOOK_LEFT` - 向左转
     - `LOOK_RIGHT` - 向右转
     - `WINK` - 眨眼
   - **示例**: `"MANUAL:ROTATE_LEFT"`

### 数据格式要求注意事项

- **编码**：所有消息均需使用 UTF-8 编码。
- **消息结束符**：不需要额外的结束符（如 `\n`），每条消息为独立的数据包。
- **错误处理**：对于无法识别的命令，服务器和客户端均应记录警告或错误日志，但不必终止连接。



## 常见问题

### Q: 为什么连接不到机器人？
- 请确保机器人和客户端在同一个网络内。
- 检查机器人服务器的 IP 地址和端口是否正确配置。
- 确保网络中无阻止 UDP 广播的防火墙。

## 贡献

欢迎任何形式的贡献！如果您发现 Bug 或者有改进建议，请提交 Issue 或发起 Pull Request。

## 联系方式
- **项目维护人**: 阿卡林真的是太可爱了
- **GitHub**: [https://github.com/AkazaAkali]
