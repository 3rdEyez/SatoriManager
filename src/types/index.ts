// 眼部运动模式
export enum EyeMode {
  Unconnected = 0,
  Auto = 1,
  Manual = 2,
  Sleep = 3,
  FacialRecognition = 4,
}

// 连接类型
export enum ConnectionType {
  None = 'none',
  UDP = 'udp',
  Bluetooth = 'bluetooth',
}

// 心跳/脉搏状态
export enum HeartbeatStatus {
  Normal = 'normal',      // 脉搏正常
  Weak = 'weak',          // 脉搏微弱
  Lost = 'lost',          // 脉搏消失
  Reviving = 'reviving',  // 电击复苏中
}

// PWM 通道值
export interface ChannelValues {
  ch1: number; // 眼球水平运动 (Yaw) (500-2500)
  ch2: number; // 眼球竖直运动 (Pitch) (500-2500)
  ch3: number; // 上眼皮运动 (500-2500)
}

// 预设动作帧
export interface ActionFrame {
  CH1: number; // -1 表示不修改，0-1 表示归一化值
  CH2: number;
  CH3: number;
  duration: number; // 毫秒
}

// 预设动作集合
export interface PresetActions {
  [actionName: string]: ActionFrame[];
}

// 电池状态
export interface BatteryStatus {
  voltage1: number;     // 电池1电压 (V)
  voltage2: number;     // 电池2电压 (V)
  percentage: number;   // 总电量百分比
  isLow: boolean;       // 是否低电量 (< 3.5V)
  isCritical: boolean;  // 是否危急 (< 3.3V)
}

// 系统状态
export interface SystemStatus {
  fps: number;              // 人脸追踪帧率
  cpuTemperature: number;   // CPU温度
  heartbeat: HeartbeatStatus;
  currentDrawLow: boolean;  // 电流是否过低 (可能导致IP5306关机)
}

// PID 参数
export interface PIDParameters {
  p: number;  // 比例系数 (0-10)
  i: number;  // 积分系数 (0-1)
  d: number;  // 微分系数 (0-1)
}

// 滤波器参数
export interface FilterParameters {
  kalmanR: number;  // 卡尔曼滤波观测噪声协方差 (0.01-10)
}

// 校准数据
export interface CalibrationData {
  centerPitch: number;  // 校准后的中心Pitch PWM值
  centerYaw: number;    // 校准后的中心Yaw PWM值
  isCalibrated: boolean;
}

// 连接状态
export interface ConnectionState {
  isConnected: boolean;
  connectionType: ConnectionType;
  serverAddress: string | null;
  serverPort: number | null;
  deviceId: string | null;
  deviceName: string | null;
  battery: BatteryStatus;
  reconnectAttempts: number;
}

// 蓝牙设备信息
export interface BluetoothDevice {
  id: string;
  name: string | null;
  rssi: number | null;
  isConnectable: boolean;
}

// 蓝牙扫描状态
export interface BluetoothScanState {
  isScanning: boolean;
  devices: BluetoothDevice[];
  error: string | null;
}

// 应用设置
export interface AppSettings {
  resetStickOnRelease: boolean;
  autoWinkEnabled: boolean;
  pwmRange: number;
  updateInterval: number;
  preferredConnectionType: ConnectionType;
  sendRateLimit: number;  // 发送频率限制 (ms)
}

// 调优参数
export interface TuningParameters {
  pid: PIDParameters;
  filter: FilterParameters;
  calibration: CalibrationData;
}

// 摇杆位置
export interface JoystickPosition {
  x: number; // -1 到 1 (Yaw)
  y: number; // -1 到 1 (Pitch)
}

// 预设动作宏定义
export const ActionMacros: Record<string, {name: string; description: string; frames: ActionFrame[]}> = {
  contempt: {
    name: '鄙视',
    description: '眼球向下翻并保持',
    frames: [
      {CH1: 0.5, CH2: 0.2, CH3: -1, duration: 300},
    ],
  },
  scan: {
    name: '扫视',
    description: '快速左右移动',
    frames: [
      {CH1: 0.2, CH2: 0.5, CH3: -1, duration: 150},
      {CH1: 0.8, CH2: 0.5, CH3: -1, duration: 150},
      {CH1: 0.2, CH2: 0.5, CH3: -1, duration: 150},
      {CH1: 0.5, CH2: 0.5, CH3: -1, duration: 200},
    ],
  },
  shy: {
    name: '害羞',
    description: '快速移开视线并闭眼',
    frames: [
      {CH1: 0.1, CH2: 0.3, CH3: 0.0, duration: 200},
      {CH1: 0.1, CH2: 0.3, CH3: 0.0, duration: 500},
      {CH1: 0.5, CH2: 0.5, CH3: 1.0, duration: 300},
    ],
  },
  wink: {
    name: '眨眼',
    description: '快速眨一次眼',
    frames: [
      {CH1: -1, CH2: -1, CH3: 0.0, duration: 100},
      {CH1: -1, CH2: -1, CH3: 1.0, duration: 100},
    ],
  },
  surprise: {
    name: '惊讶',
    description: '瞳孔扩大效果',
    frames: [
      {CH1: 0.5, CH2: 0.7, CH3: 1.0, duration: 200},
      {CH1: 0.5, CH2: 0.5, CH3: 1.0, duration: 500},
    ],
  },
};

// 协议消息常量
export const ProtocolMessages = {
  DISCOVERY_REQUEST: 'SatoriEye_DISCOVERY_REQUEST',
  DISCOVERY_RESPONSE: 'SatoriEye_DISCOVERY_RESPONSE',
  HEARTBEAT_REQUEST: 'SatoriEye_HEARTBEAT_REQUEST',
  HEARTBEAT_RESPONSE: 'SatoriEye_HEARTBEAT_RESPONSE',
  DISCONNECT: 'SatoriEye_DISCONNECT',
  SET_MODE: 'SET_MODE',
  SET_MODE_SUCCESS: 'SET_MODE_SUCCESS',
  SET_PID: 'SET_PID',
  SET_FILTER: 'SET_FILTER',
  CALIBRATE: 'CALIBRATE',
  REVIVE: 'REVIVE',  // 电击复苏
} as const;

// PWM 常量
export const PWM_CONSTANTS = {
  MIN_VALUE: 500,
  MAX_VALUE: 2500,
  CENTER_VALUE: 1500,
  DEFAULT_RANGE: 250,
  DEFAULT_INTERVAL: 2550,
} as const;

// 电池常量
export const BATTERY_CONSTANTS = {
  FULL_VOLTAGE: 4.2,      // 满电电压
  NOMINAL_VOLTAGE: 3.7,   // 标称电压
  LOW_VOLTAGE: 3.5,       // 低电压阈值
  CRITICAL_VOLTAGE: 3.3,  // 危急电压阈值
  CUTOFF_VOLTAGE: 3.0,    // 截止电压
} as const;

// 网络常量
export const NETWORK_CONSTANTS = {
  CLIENT_PORT: 8889,
  SERVER_PORT: 8888,
  BROADCAST_ADDRESS: '224.0.0.1',
  LOCALHOST: '127.0.0.1',
  HEARTBEAT_INTERVAL: 20000,
  RECONNECT_INTERVAL: 10000,
  MAX_RECONNECT_ATTEMPTS: 5,
} as const;

// 蓝牙常量
export const BLUETOOTH_CONSTANTS = {
  SERVICE_UUID: '6e400001-b5a3-f393-e0a9-e50e24dcca9e',
  TX_CHARACTERISTIC_UUID: '6e400002-b5a3-f393-e0a9-e50e24dcca9e',
  RX_CHARACTERISTIC_UUID: '6e400003-b5a3-f393-e0a9-e50e24dcca9e',
  SCAN_TIMEOUT: 10000,
  DEVICE_NAME_PREFIX: 'SatoriEye',
  CONNECTION_TIMEOUT: 10000,
  MTU_SIZE: 512,
  SEND_RATE_LIMIT: 50,  // 50ms 发送频率限制
} as const;

// PID 默认值
export const PID_DEFAULTS: PIDParameters = {
  p: 1.0,
  i: 0.1,
  d: 0.05,
};

// 滤波器默认值
export const FILTER_DEFAULTS: FilterParameters = {
  kalmanR: 1.0,
};

// 模式名称映射
export const MODE_NAMES: Record<EyeMode, string> = {
  [EyeMode.Unconnected]: '未连接',
  [EyeMode.Auto]: '自动追踪',
  [EyeMode.Manual]: '手动操控',
  [EyeMode.Sleep]: '休眠',
  [EyeMode.FacialRecognition]: '人脸追踪',
};

// 心跳状态名称
export const HEARTBEAT_NAMES: Record<HeartbeatStatus, string> = {
  [HeartbeatStatus.Normal]: '脉搏正常',
  [HeartbeatStatus.Weak]: '脉搏微弱',
  [HeartbeatStatus.Lost]: '脉搏消失',
  [HeartbeatStatus.Reviving]: '电击复苏中',
};

// ========== 视觉伺服相关类型 ==========

// 视频流配置
export interface VideoStreamConfig {
  enabled: boolean;
  targetFPS: number;
  resolution: {
    width: number;
    height: number;
  };
  quality: 'low' | 'medium' | 'high';
}

// 视频帧数据
export interface VideoFrame {
  frameId: number;
  data: Uint8Array;
  timestamp: number;
  width: number;
  height: number;
}

// 视频流状态
export interface VideoStreamState {
  isReceiving: boolean;
  currentFPS: number;
  droppedFrames: number;
  avgLatency: number;
}

// 视频流默认配置
export const VIDEO_STREAM_DEFAULTS: VideoStreamConfig = {
  enabled: false,
  targetFPS: 30,
  resolution: {
    width: 640,
    height: 480,
  },
  quality: 'medium',
};

// ========== TCP 视频流相关类型 ==========

// ESP32 设备信息 (从 UDP 心跳发现)
export interface ESP32Device {
  deviceId: string;
  ip: string;
  tcpPort: number;
  heartbeatPort: number;
  fps: number;
  lastSeen: number; // 时间戳
  rssi?: number; // 信号强度 (可选)
}

// TCP 视频配置
export interface TCPVideoConfig {
  host: string;
  port: number;
  reconnectOnError: boolean;
  connectionTimeout: number;
}

// 设备发现状态
export interface DeviceDiscoveryState {
  isDiscovering: boolean;
  devices: ESP32Device[];
  selectedDevice: ESP32Device | null;
  error: string | null;
}

// 帧数据包头部 (12 字节)
export interface FramePacketHeader {
  magic: number; // 0xFFD8 (JPEG magic)
  frameId: number; // 帧 ID
  totalChunks: number; // 总块数
  chunkId: number; // 当前块 ID
  chunkSize: number; // 数据大小
}

// TCP 视频流常量
export const TCP_VIDEO_CONSTANTS = {
  DISCOVERY_PORT: 8889, // UDP 发现端口
  VIDEO_PORT: 8888, // TCP 视频流端口
  DEVICE_STALE_TIMEOUT: 10000, // 设备过期时间 (10秒)
  HEARTBEAT_INTERVAL: 1000, // 心跳间隔 (1秒)
  CONNECTION_TIMEOUT: 5000, // 连接超时 (5秒)
  READ_TIMEOUT: 10000, // 读取超时 (10秒)
  PACKET_HEADER_SIZE: 12, // 数据包头部大小
  JPEG_MAGIC: 0xFFD8, // JPEG 魔数
} as const;
