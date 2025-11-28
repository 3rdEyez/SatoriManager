import dgram from 'react-native-udp';
import {
  EyeMode,
  ChannelValues,
  ConnectionState,
  ProtocolMessages,
  PWM_CONSTANTS,
  NETWORK_CONSTANTS,
  MODE_NAMES,
  ActionFrame,
} from '../types';

type UdpSocket = ReturnType<typeof dgram.createSocket>;

export type ConnectionCallback = (state: ConnectionState) => void;
export type ModeCallback = (mode: EyeMode) => void;
export type BatteryCallback = (battery: number) => void;

class MobileClient {
  private socket: UdpSocket | null = null;
  private serverAddress: string | null = null;
  private serverPort: number = NETWORK_CONSTANTS.SERVER_PORT;
  private heartbeatTimer: ReturnType<typeof setInterval> | null = null;
  private autoModeTimer: ReturnType<typeof setInterval> | null = null;
  private autoWinkTimer: ReturnType<typeof setTimeout> | null = null;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;

  private currentMode: EyeMode = EyeMode.Unconnected;
  private battery: number = 0;
  private reconnectAttempts: number = 0;
  private isConnected: boolean = false;
  private lastHeartbeatResponse: number = Date.now();

  private pwmRange: number = PWM_CONSTANTS.DEFAULT_RANGE;
  private updateInterval: number = PWM_CONSTANTS.DEFAULT_INTERVAL;
  private autoWinkEnabled: boolean = true;

  private currentChannelValues: ChannelValues = {
    ch1: PWM_CONSTANTS.CENTER_VALUE,
    ch2: PWM_CONSTANTS.CENTER_VALUE,
    ch3: PWM_CONSTANTS.CENTER_VALUE,
  };

  // 回调函数
  private onConnectionChange: ConnectionCallback | null = null;
  private onModeChange: ModeCallback | null = null;
  private onBatteryChange: BatteryCallback | null = null;

  constructor() {
    this.setupSocket();
  }

  // 设置回调
  setCallbacks(
    onConnection: ConnectionCallback,
    onMode: ModeCallback,
    onBattery: BatteryCallback,
  ) {
    this.onConnectionChange = onConnection;
    this.onModeChange = onMode;
    this.onBatteryChange = onBattery;
  }

  // 初始化 Socket
  private setupSocket() {
    try {
      this.socket = dgram.createSocket({type: 'udp4'});

      this.socket.on('message', (data: Buffer, rinfo: {address: string; port: number}) => {
        this.handleMessage(data.toString(), rinfo.address, rinfo.port);
      });

      this.socket.on('error', (err: Error) => {
        console.error('UDP Socket error:', err);
      });

      this.socket.bind(NETWORK_CONSTANTS.CLIENT_PORT, () => {
        console.log(`UDP Socket bound to port ${NETWORK_CONSTANTS.CLIENT_PORT}`);
      });
    } catch (error) {
      console.error('Failed to setup socket:', error);
    }
  }

  // 处理收到的消息
  private handleMessage(message: string, address: string, port: number) {
    console.log(`Received: ${message} from ${address}:${port}`);

    if (message.startsWith(ProtocolMessages.DISCOVERY_RESPONSE)) {
      this.handleDiscoveryResponse(message, address, port);
    } else if (message.startsWith(ProtocolMessages.HEARTBEAT_RESPONSE)) {
      this.handleHeartbeatResponse(message);
    } else if (message.startsWith(ProtocolMessages.SET_MODE_SUCCESS)) {
      this.handleModeSuccess(message);
    }
  }

  // 处理发现响应
  private handleDiscoveryResponse(message: string, address: string, port: number) {
    const parts = message.split(',');
    if (parts.length >= 2) {
      this.battery = parseInt(parts[1], 10) || 0;
      this.onBatteryChange?.(this.battery);
    }

    this.serverAddress = address;
    this.serverPort = port;
    this.isConnected = true;
    this.reconnectAttempts = 0;
    this.lastHeartbeatResponse = Date.now();

    this.notifyConnectionChange();
    this.setMode(EyeMode.Manual);
    this.startHeartbeat();
    this.startAutoWink();

    console.log(`Connected to server at ${address}:${port}`);
  }

  // 处理心跳响应
  private handleHeartbeatResponse(message: string) {
    this.lastHeartbeatResponse = Date.now();
    const parts = message.split(',');
    if (parts.length >= 2) {
      this.battery = parseInt(parts[1], 10) || 0;
      this.onBatteryChange?.(this.battery);
    }
  }

  // 处理模式切换成功
  private handleModeSuccess(message: string) {
    const parts = message.split(':');
    if (parts.length >= 2) {
      const modeName = parts[1];
      const mode = Object.entries(MODE_NAMES).find(
        ([, name]) => name === modeName,
      )?.[0];
      if (mode !== undefined) {
        this.currentMode = parseInt(mode, 10) as EyeMode;
        this.onModeChange?.(this.currentMode);
      }
    }
  }

  // 通知连接状态变化
  private notifyConnectionChange() {
    this.onConnectionChange?.({
      isConnected: this.isConnected,
      serverAddress: this.serverAddress,
      serverPort: this.serverPort,
      battery: this.battery,
      reconnectAttempts: this.reconnectAttempts,
    });
  }

  // 发送消息
  private sendMessage(message: string, address?: string, port?: number) {
    const targetAddress = address || this.serverAddress;
    const targetPort = port || this.serverPort;

    if (!this.socket || !targetAddress) {
      console.warn('Cannot send message: socket or address not available');
      return;
    }

    const buffer = Buffer.from(message);
    this.socket.send(buffer, 0, buffer.length, targetPort, targetAddress, (err) => {
      if (err) {
        console.error('Send error:', err);
      }
    });
  }

  // 查找服务器
  findServer() {
    console.log('Searching for server...');
    this.sendMessage(
      ProtocolMessages.DISCOVERY_REQUEST,
      NETWORK_CONSTANTS.BROADCAST_ADDRESS,
      NETWORK_CONSTANTS.SERVER_PORT,
    );
    // 同时发送到本地回环地址
    this.sendMessage(
      ProtocolMessages.DISCOVERY_REQUEST,
      NETWORK_CONSTANTS.LOCALHOST,
      NETWORK_CONSTANTS.SERVER_PORT,
    );
  }

  // 断开连接
  disconnect() {
    if (this.isConnected) {
      this.sendMessage(ProtocolMessages.DISCONNECT);
    }

    this.stopHeartbeat();
    this.stopAutoMode();
    this.stopAutoWink();

    this.isConnected = false;
    this.serverAddress = null;
    this.currentMode = EyeMode.Unconnected;

    this.notifyConnectionChange();
    this.onModeChange?.(EyeMode.Unconnected);
  }

  // 启动心跳
  private startHeartbeat() {
    this.stopHeartbeat();
    this.heartbeatTimer = setInterval(() => {
      this.checkConnection();
    }, NETWORK_CONSTANTS.HEARTBEAT_INTERVAL);
  }

  // 停止心跳
  private stopHeartbeat() {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
  }

  // 检查连接状态
  private checkConnection() {
    const now = Date.now();
    const timeSinceLastResponse = now - this.lastHeartbeatResponse;

    if (timeSinceLastResponse > NETWORK_CONSTANTS.HEARTBEAT_INTERVAL * 3) {
      console.log('Connection lost, attempting to reconnect...');
      this.handleConnectionLost();
      return;
    }

    this.sendMessage(ProtocolMessages.HEARTBEAT_REQUEST);
  }

  // 处理连接丢失
  private handleConnectionLost() {
    this.isConnected = false;
    this.notifyConnectionChange();

    if (this.reconnectAttempts < NETWORK_CONSTANTS.MAX_RECONNECT_ATTEMPTS) {
      this.reconnectAttempts++;
      this.reconnectTimer = setTimeout(() => {
        this.findServer();
      }, NETWORK_CONSTANTS.RECONNECT_INTERVAL);
    } else {
      console.log('Max reconnect attempts reached');
      this.disconnect();
    }
  }

  // 设置模式
  setMode(mode: EyeMode) {
    if (mode === this.currentMode) return;

    this.currentMode = mode;
    this.onModeChange?.(mode);

    if (mode === EyeMode.Auto) {
      this.startAutoMode();
    } else {
      this.stopAutoMode();
    }

    // 发送模式切换命令
    if (this.isConnected && mode !== EyeMode.Auto && mode !== EyeMode.Manual) {
      this.sendMessage(`${ProtocolMessages.SET_MODE}:${MODE_NAMES[mode]}`);
    }
  }

  // 启动自动模式
  private startAutoMode() {
    this.stopAutoMode();
    this.autoModeTimer = setInterval(() => {
      this.generateRandomPWM();
    }, this.updateInterval);
  }

  // 停止自动模式
  private stopAutoMode() {
    if (this.autoModeTimer) {
      clearInterval(this.autoModeTimer);
      this.autoModeTimer = null;
    }
  }

  // 生成随机 PWM 值（正态分布）
  private generateRandomPWM() {
    const gaussianRandom = () => {
      let u = 0,
        v = 0;
      while (u === 0) u = Math.random();
      while (v === 0) v = Math.random();
      return Math.sqrt(-2.0 * Math.log(u)) * Math.cos(2.0 * Math.PI * v);
    };

    const center = PWM_CONSTANTS.CENTER_VALUE;
    const ch1 = Math.max(
      PWM_CONSTANTS.MIN_VALUE,
      Math.min(PWM_CONSTANTS.MAX_VALUE, center + gaussianRandom() * this.pwmRange),
    );
    const ch2 = Math.max(
      PWM_CONSTANTS.MIN_VALUE,
      Math.min(PWM_CONSTANTS.MAX_VALUE, center + gaussianRandom() * this.pwmRange),
    );

    this.updateChannelValues(ch1, ch2, this.currentChannelValues.ch3, true, this.updateInterval);
  }

  // 启动自动眨眼
  private startAutoWink() {
    if (!this.autoWinkEnabled) return;

    const scheduleNextWink = () => {
      const interval = 3000 + Math.random() * 4000; // 3-7秒随机间隔
      this.autoWinkTimer = setTimeout(() => {
        this.executeWink();
        scheduleNextWink();
      }, interval);
    };

    scheduleNextWink();
  }

  // 停止自动眨眼
  private stopAutoWink() {
    if (this.autoWinkTimer) {
      clearTimeout(this.autoWinkTimer);
      this.autoWinkTimer = null;
    }
  }

  // 执行眨眼动作
  private executeWink() {
    const winkFrames: ActionFrame[] = [
      {CH1: -1, CH2: -1, CH3: 0.0, duration: 100},
      {CH1: -1, CH2: -1, CH3: 1.0, duration: 100},
    ];
    this.playFrames(winkFrames);
  }

  // 设置自动眨眼
  setAutoWinkEnabled(enabled: boolean) {
    this.autoWinkEnabled = enabled;
    if (enabled && this.isConnected) {
      this.startAutoWink();
    } else {
      this.stopAutoWink();
    }
  }

  // 设置自动模式参数
  setAutoModeParameters(range: number, interval: number) {
    this.pwmRange = range;
    this.updateInterval = interval;

    if (this.currentMode === EyeMode.Auto) {
      this.startAutoMode();
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
    this.currentChannelValues = {ch1, ch2, ch3};

    let message: string;
    if (smooth && duration > 0) {
      message = `SMOOTH:CH1:${Math.round(ch1)}CH2:${Math.round(ch2)}CH3:${Math.round(ch3)}MS:${duration}`;
    } else {
      message = `CH1:${Math.round(ch1)}CH2:${Math.round(ch2)}CH3:${Math.round(ch3)}`;
    }

    this.sendMessage(message);
  }

  // 使用归一化值更新通道
  updateChannelValuesWithProportions(ch1Prop: number, ch2Prop: number, ch3Prop: number) {
    const range = PWM_CONSTANTS.MAX_VALUE - PWM_CONSTANTS.MIN_VALUE;
    const ch1 = ch1Prop >= 0 ? PWM_CONSTANTS.MIN_VALUE + ch1Prop * range : this.currentChannelValues.ch1;
    const ch2 = ch2Prop >= 0 ? PWM_CONSTANTS.MIN_VALUE + ch2Prop * range : this.currentChannelValues.ch2;
    const ch3 = ch3Prop >= 0 ? PWM_CONSTANTS.MIN_VALUE + ch3Prop * range : this.currentChannelValues.ch3;

    this.updateChannelValues(ch1, ch2, ch3);
  }

  // 播放动作帧序列
  async playFrames(frames: ActionFrame[]) {
    for (const frame of frames) {
      const ch1Prop = frame.CH1;
      const ch2Prop = frame.CH2;
      const ch3Prop = frame.CH3;

      const range = PWM_CONSTANTS.MAX_VALUE - PWM_CONSTANTS.MIN_VALUE;
      const ch1 = ch1Prop >= 0 ? PWM_CONSTANTS.MIN_VALUE + ch1Prop * range : this.currentChannelValues.ch1;
      const ch2 = ch2Prop >= 0 ? PWM_CONSTANTS.MIN_VALUE + ch2Prop * range : this.currentChannelValues.ch2;
      const ch3 = ch3Prop >= 0 ? PWM_CONSTANTS.MIN_VALUE + ch3Prop * range : this.currentChannelValues.ch3;

      this.updateChannelValues(ch1, ch2, ch3, true, frame.duration);
      await new Promise((resolve) => setTimeout(resolve, frame.duration));
    }
  }

  // 获取当前状态
  getConnectionState(): ConnectionState {
    return {
      isConnected: this.isConnected,
      serverAddress: this.serverAddress,
      serverPort: this.serverPort,
      battery: this.battery,
      reconnectAttempts: this.reconnectAttempts,
    };
  }

  getCurrentMode(): EyeMode {
    return this.currentMode;
  }

  getBattery(): number {
    return this.battery;
  }

  // 销毁
  // 发送原始消息 (用于调优指令等)
  sendRawMessage(message: string) {
    this.sendMessage(message);
  }

  destroy() {
    this.disconnect();
    if (this.socket) {
      this.socket.close();
      this.socket = null;
    }
  }
}

// 单例导出
export const mobileClient = new MobileClient();
export default MobileClient;
