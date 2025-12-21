import {mobileClient} from './MobileClient';
import {bluetoothClient} from './BluetoothClient';
import {
  VisualServoController,
  VisualServoConfig,
  VisualServoInput,
  VisualServoOutput,
  PIDDebugInfo,
  DEFAULT_VISUAL_SERVO_CONFIG,
} from './VisualServoController';
import {getUdpDiscoveryService} from './UdpDiscoveryService';
import {getTcpVideoClient} from './TcpVideoClient';
import {getTcpFrameAssembler} from './TcpFrameAssembler';
import {
  ConnectionType,
  ConnectionState,
  EyeMode,
  BluetoothDevice,
  BluetoothScanState,
  ActionFrame,
  BatteryStatus,
  SystemStatus,
  PIDParameters,
  FilterParameters,
  ProtocolMessages,
  VideoStreamConfig,
  VideoFrame,
  ESP32Device,
} from '../types';

export type ConnectionCallback = (state: ConnectionState) => void;
export type ModeCallback = (mode: EyeMode) => void;
export type BatteryCallback = (battery: BatteryStatus) => void;
export type ScanCallback = (state: BluetoothScanState) => void;
export type SystemStatusCallback = (status: SystemStatus) => void;
export type VideoFrameCallback = (frame: VideoFrame) => void;
export type DeviceDiscoveryCallback = (devices: ESP32Device[]) => void;

// 默认电池状态
const defaultBatteryStatus: BatteryStatus = {
  voltage1: 0,
  voltage2: 0,
  percentage: 0,
  isLow: false,
  isCritical: false,
};

// 从单电压值转换为 BatteryStatus
const batteryFromVoltage = (voltage: number): BatteryStatus => {
  const FULL_VOLTAGE = 4.2;
  const LOW_VOLTAGE = 3.5;
  const CRITICAL_VOLTAGE = 3.3;
  const CUTOFF_VOLTAGE = 3.0;

  const percentage = Math.max(0, Math.min(100,
    ((voltage - CUTOFF_VOLTAGE) / (FULL_VOLTAGE - CUTOFF_VOLTAGE)) * 100
  ));

  return {
    voltage1: voltage,
    voltage2: voltage, // 假设两个电池电压相同
    percentage: Math.round(percentage),
    isLow: voltage < LOW_VOLTAGE,
    isCritical: voltage < CRITICAL_VOLTAGE,
  };
};

class ConnectionManager {
  private currentConnectionType: ConnectionType = ConnectionType.None;
  private connectionState: ConnectionState = {
    isConnected: false,
    connectionType: ConnectionType.None,
    serverAddress: null,
    serverPort: null,
    deviceId: null,
    deviceName: null,
    battery: {...defaultBatteryStatus},
    reconnectAttempts: 0,
  };

  private onConnectionChange: ConnectionCallback | null = null;
  private onModeChange: ModeCallback | null = null;
  private onBatteryChange: BatteryCallback | null = null;
  private onScanChange: ScanCallback | null = null;
  private onSystemStatusChange: SystemStatusCallback | null = null;
  private onVideoFrame: VideoFrameCallback | null = null;
  private onDeviceDiscovery: DeviceDiscoveryCallback | null = null;

  // 视觉伺服控制器
  private visualServoController: VisualServoController | null = null;
  private visualServoEnabled: boolean = false;

  // TCP 视频流服务
  private discoveryService = getUdpDiscoveryService();
  private tcpVideoClient = getTcpVideoClient();
  private tcpFrameAssembler = getTcpFrameAssembler();

  constructor() {
    this.setupCallbacks();
    this.setupTcpVideoServices();
  }

  // 设置回调
  setCallbacks(
    onConnection: ConnectionCallback,
    onMode: ModeCallback,
    onBattery: BatteryCallback,
    onScan?: ScanCallback,
    onSystemStatus?: SystemStatusCallback,
    onVideoFrame?: VideoFrameCallback,
    onDeviceDiscovery?: DeviceDiscoveryCallback,
  ) {
    this.onConnectionChange = onConnection;
    this.onModeChange = onMode;
    this.onBatteryChange = onBattery;
    this.onScanChange = onScan || null;
    this.onSystemStatusChange = onSystemStatus || null;
    this.onVideoFrame = onVideoFrame || null;
    this.onDeviceDiscovery = onDeviceDiscovery || null;
  }

  // 设置内部回调
  private setupCallbacks() {
    // UDP 回调
    mobileClient.setCallbacks(
      (state) => {
        if (this.currentConnectionType === ConnectionType.UDP) {
          const batteryStatus = batteryFromVoltage(state.battery);
          this.updateConnectionState({
            isConnected: state.isConnected,
            connectionType: state.isConnected ? ConnectionType.UDP : ConnectionType.None,
            serverAddress: state.serverAddress,
            serverPort: state.serverPort,
            deviceId: null,
            deviceName: null,
            battery: batteryStatus,
            reconnectAttempts: state.reconnectAttempts,
          });
        }
      },
      (mode) => {
        if (this.currentConnectionType === ConnectionType.UDP) {
          this.onModeChange?.(mode);
        }
      },
      (battery) => {
        if (this.currentConnectionType === ConnectionType.UDP) {
          const batteryStatus = batteryFromVoltage(battery);
          this.connectionState.battery = batteryStatus;
          this.onBatteryChange?.(batteryStatus);
        }
      },
    );

    // 蓝牙回调
    bluetoothClient.setCallbacks(
      (isConnected, device) => {
        if (this.currentConnectionType === ConnectionType.Bluetooth || !this.connectionState.isConnected) {
          this.updateConnectionState({
            isConnected,
            connectionType: isConnected ? ConnectionType.Bluetooth : ConnectionType.None,
            serverAddress: null,
            serverPort: null,
            deviceId: device?.id || null,
            deviceName: device?.name || null,
            battery: this.connectionState.battery,
            reconnectAttempts: 0,
          });
        }
      },
      (scanState) => {
        this.onScanChange?.(scanState);
      },
      (mode) => {
        if (this.currentConnectionType === ConnectionType.Bluetooth) {
          this.onModeChange?.(mode);
        }
      },
      (battery) => {
        if (this.currentConnectionType === ConnectionType.Bluetooth) {
          const batteryStatus = batteryFromVoltage(battery);
          this.connectionState.battery = batteryStatus;
          this.onBatteryChange?.(batteryStatus);
        }
      },
    );
  }

  // 设置 TCP 视频服务回调
  private setupTcpVideoServices() {
    // 设置设备发现回调
    this.discoveryService.onDeviceUpdate((devices) => {
      this.onDeviceDiscovery?.(devices);
    });

    // 设置 TCP 视频客户端回调
    this.tcpVideoClient.onPacketReceived((packet) => {
      this.tcpFrameAssembler.onPacket(packet);
    });

    // 设置帧组装完成回调
    this.tcpFrameAssembler.setFrameCallback((frame) => {
      this.onVideoFrame?.(frame);
    });
  }

  // 更新连接状态
  private updateConnectionState(state: ConnectionState) {
    this.connectionState = state;
    this.currentConnectionType = state.connectionType;
    this.onConnectionChange?.(state);
  }

  // ========== UDP 连接 ==========

  // 通过 UDP 连接
  connectUDP() {
    this.currentConnectionType = ConnectionType.UDP;
    mobileClient.findServer();
  }

  // ========== 蓝牙连接 ==========

  // 开始蓝牙扫描
  async startBluetoothScan() {
    await bluetoothClient.startScan();
  }

  // 停止蓝牙扫描
  stopBluetoothScan() {
    bluetoothClient.stopScan();
  }

  // 通过蓝牙连接设备
  async connectBluetooth(deviceId: string): Promise<boolean> {
    this.currentConnectionType = ConnectionType.Bluetooth;
    return await bluetoothClient.connect(deviceId);
  }

  // 获取蓝牙扫描状态
  getBluetoothScanState(): BluetoothScanState {
    return bluetoothClient.getScanState();
  }

  // ========== 通用操作 ==========

  // 断开连接
  disconnect() {
    switch (this.currentConnectionType) {
      case ConnectionType.UDP:
        mobileClient.disconnect();
        break;
      case ConnectionType.Bluetooth:
        bluetoothClient.disconnect();
        break;
    }
    this.currentConnectionType = ConnectionType.None;
  }

  // 设置模式
  setMode(mode: EyeMode) {
    switch (this.currentConnectionType) {
      case ConnectionType.UDP:
        mobileClient.setMode(mode);
        break;
      case ConnectionType.Bluetooth:
        bluetoothClient.setMode(mode);
        break;
    }
  }

  // 更新通道值
  updateChannelValues(
    ch1: number,
    ch2: number,
    ch3: number,
    smooth: boolean = false,
    duration: number = 0,
  ) {
    switch (this.currentConnectionType) {
      case ConnectionType.UDP:
        mobileClient.updateChannelValues(ch1, ch2, ch3, smooth, duration);
        break;
      case ConnectionType.Bluetooth:
        bluetoothClient.updateChannelValues(ch1, ch2, ch3, smooth, duration);
        break;
    }
  }

  // 使用归一化值更新通道
  updateChannelValuesWithProportions(ch1Prop: number, ch2Prop: number, ch3Prop: number) {
    switch (this.currentConnectionType) {
      case ConnectionType.UDP:
        mobileClient.updateChannelValuesWithProportions(ch1Prop, ch2Prop, ch3Prop);
        break;
      case ConnectionType.Bluetooth:
        bluetoothClient.updateChannelValuesWithProportions(ch1Prop, ch2Prop, ch3Prop);
        break;
    }
  }

  // 播放动作帧
  async playFrames(frames: ActionFrame[]) {
    switch (this.currentConnectionType) {
      case ConnectionType.UDP:
        await mobileClient.playFrames(frames);
        break;
      case ConnectionType.Bluetooth:
        await bluetoothClient.playFrames(frames);
        break;
    }
  }

  // 设置自动眨眼
  setAutoWinkEnabled(enabled: boolean) {
    mobileClient.setAutoWinkEnabled(enabled);
    bluetoothClient.setAutoWinkEnabled(enabled);
  }

  // 设置自动模式参数
  setAutoModeParameters(range: number, interval: number) {
    mobileClient.setAutoModeParameters(range, interval);
    bluetoothClient.setAutoModeParameters(range, interval);
  }

  // 获取连接状态
  getConnectionState(): ConnectionState {
    return this.connectionState;
  }

  // 获取当前连接类型
  getConnectionType(): ConnectionType {
    return this.currentConnectionType;
  }

  // 检查是否已连接
  isConnected(): boolean {
    return this.connectionState.isConnected;
  }

  // ========== 调优操作 ==========

  // 设置 PID 参数
  setPIDParameters(params: PIDParameters) {
    const message = `${ProtocolMessages.SET_PID}:${params.p},${params.i},${params.d}`;
    switch (this.currentConnectionType) {
      case ConnectionType.UDP:
        mobileClient.sendRawMessage(message);
        break;
      case ConnectionType.Bluetooth:
        bluetoothClient.sendRawMessage(message);
        break;
    }
  }

  // 设置滤波器参数
  setFilterParameters(params: FilterParameters) {
    const message = `${ProtocolMessages.SET_FILTER}:${params.kalmanR}`;
    switch (this.currentConnectionType) {
      case ConnectionType.UDP:
        mobileClient.sendRawMessage(message);
        break;
      case ConnectionType.Bluetooth:
        bluetoothClient.sendRawMessage(message);
        break;
    }
  }

  // 校准中心位置
  calibrateCenter() {
    const message = ProtocolMessages.CALIBRATE;
    switch (this.currentConnectionType) {
      case ConnectionType.UDP:
        mobileClient.sendRawMessage(message);
        break;
      case ConnectionType.Bluetooth:
        bluetoothClient.sendRawMessage(message);
        break;
    }
  }

  // 电击复苏 (唤醒IP5306)
  revive() {
    const message = ProtocolMessages.REVIVE;
    switch (this.currentConnectionType) {
      case ConnectionType.UDP:
        mobileClient.sendRawMessage(message);
        break;
      case ConnectionType.Bluetooth:
        bluetoothClient.sendRawMessage(message);
        break;
    }
  }

  // ========== 视频流控制 ==========

  /**
   * 启动设备发现
   */
  startDeviceDiscovery() {
    this.discoveryService.startDiscovery();
    console.log('Device discovery started');
  }

  /**
   * 停止设备发现
   */
  stopDeviceDiscovery() {
    this.discoveryService.stopDiscovery();
    console.log('Device discovery stopped');
  }

  /**
   * 获取已发现的设备列表
   */
  getDiscoveredDevices(): ESP32Device[] {
    return this.discoveryService.getDiscoveredDevices();
  }

  /**
   * 启动视频流 (TCP)
   * @param device ESP32 设备信息
   * @param config 视频流配置
   */
  startVideoStream(device: ESP32Device, config?: VideoStreamConfig) {
    // 连接到 TCP 视频服务器
    this.tcpVideoClient.connect(device.ip, device.tcpPort, true);

    // 重置统计信息
    this.tcpFrameAssembler.resetStats();

    console.log(`Video stream started: ${device.ip}:${device.tcpPort}`, config);
  }

  /**
   * 停止视频流
   */
  stopVideoStream() {
    // 断开 TCP 连接
    this.tcpVideoClient.disconnect();
    console.log('Video stream stopped');
  }

  /**
   * 获取视频流统计信息
   */
  getVideoStreamStats() {
    return this.tcpFrameAssembler.getStats();
  }

  // ========== 视觉伺服控制 ==========

  /**
   * 启动视觉伺服模式
   * @param config 视觉伺服配置
   */
  startVisualServo(config: VisualServoConfig = DEFAULT_VISUAL_SERVO_CONFIG) {
    if (!this.visualServoController) {
      this.visualServoController = new VisualServoController(config);
    } else {
      this.visualServoController.updateConfig(config);
    }

    this.visualServoEnabled = true;
    console.log('Visual servo started with config:', config);
  }

  /**
   * 停止视觉伺服模式
   */
  stopVisualServo() {
    this.visualServoEnabled = false;

    if (this.visualServoController) {
      this.visualServoController.reset();
    }

    console.log('Visual servo stopped');
  }

  /**
   * 更新视觉伺服控制
   * 应由 VisionScreen 在每次人脸检测结果后调用
   * @param input 控制输入（人脸位置、摇杆输入、模式）
   */
  updateVisualServo(input: VisualServoInput): VisualServoOutput | null {
    if (!this.visualServoEnabled || !this.visualServoController) {
      return null;
    }

    // 计算控制输出
    const output = this.visualServoController.compute(input);

    // 如果需要发送，则更新通道值
    if (output.shouldSend) {
      this.updateChannelValues(output.ch1, output.ch2, -1, false, 0);
    }

    return output;
  }

  /**
   * 更新视觉伺服 PID 参数
   * @param params PID 参数
   */
  updateVisualServoPID(params: Partial<PIDParameters>) {
    if (this.visualServoController) {
      this.visualServoController.updatePIDParams(params);
      console.log('Visual servo PID updated:', params);
    }
  }

  /**
   * 更新视觉伺服配置
   * @param config 配置更新
   */
  updateVisualServoConfig(config: Partial<VisualServoConfig>) {
    if (this.visualServoController) {
      this.visualServoController.updateConfig(config);
      console.log('Visual servo config updated:', config);
    }
  }

  /**
   * 获取视觉伺服调试信息
   */
  getVisualServoDebugInfo(): PIDDebugInfo | null {
    if (this.visualServoController) {
      return this.visualServoController.getDebugInfo();
    }
    return null;
  }

  /**
   * 获取视觉伺服配置
   */
  getVisualServoConfig(): VisualServoConfig | null {
    if (this.visualServoController) {
      return this.visualServoController.getConfig();
    }
    return null;
  }

  /**
   * 检查视觉伺服是否启用
   */
  isVisualServoEnabled(): boolean {
    return this.visualServoEnabled;
  }

  // 销毁
  destroy() {
    this.stopVisualServo();
    this.visualServoController = null;
    mobileClient.destroy();
    bluetoothClient.destroy();
  }
}

// 单例导出
export const connectionManager = new ConnectionManager();
export default ConnectionManager;
