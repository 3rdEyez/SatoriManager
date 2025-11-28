import {BleManager, Device, Characteristic, State} from 'react-native-ble-plx';
import {Platform, PermissionsAndroid} from 'react-native';
import {
  EyeMode,
  BluetoothDevice,
  BluetoothScanState,
  ProtocolMessages,
  PWM_CONSTANTS,
  BLUETOOTH_CONSTANTS,
  NETWORK_CONSTANTS,
  MODE_NAMES,
  ActionFrame,
} from '../types';

export type BluetoothConnectionCallback = (isConnected: boolean, device?: BluetoothDevice) => void;
export type BluetoothScanCallback = (state: BluetoothScanState) => void;
export type ModeCallback = (mode: EyeMode) => void;
export type BatteryCallback = (battery: number) => void;

class BluetoothClient {
  private manager: BleManager;
  private connectedDevice: Device | null = null;
  private txCharacteristic: Characteristic | null = null;
  private rxCharacteristic: Characteristic | null = null;

  private currentMode: EyeMode = EyeMode.Unconnected;
  private battery: number = 0;
  private isConnected: boolean = false;

  private heartbeatTimer: ReturnType<typeof setInterval> | null = null;
  private autoModeTimer: ReturnType<typeof setInterval> | null = null;
  private autoWinkTimer: ReturnType<typeof setTimeout> | null = null;

  private pwmRange: number = PWM_CONSTANTS.DEFAULT_RANGE;
  private updateInterval: number = PWM_CONSTANTS.DEFAULT_INTERVAL;
  private autoWinkEnabled: boolean = true;

  private currentChannelValues = {
    ch1: PWM_CONSTANTS.CENTER_VALUE,
    ch2: PWM_CONSTANTS.CENTER_VALUE,
    ch3: PWM_CONSTANTS.CENTER_VALUE,
  };

  // 回调
  private onConnectionChange: BluetoothConnectionCallback | null = null;
  private onScanStateChange: BluetoothScanCallback | null = null;
  private onModeChange: ModeCallback | null = null;
  private onBatteryChange: BatteryCallback | null = null;

  // 扫描状态
  private scanState: BluetoothScanState = {
    isScanning: false,
    devices: [],
    error: null,
  };

  constructor() {
    this.manager = new BleManager();
    this.setupBleStateListener();
  }

  // 设置回调
  setCallbacks(
    onConnection: BluetoothConnectionCallback,
    onScan: BluetoothScanCallback,
    onMode: ModeCallback,
    onBattery: BatteryCallback,
  ) {
    this.onConnectionChange = onConnection;
    this.onScanStateChange = onScan;
    this.onModeChange = onMode;
    this.onBatteryChange = onBattery;
  }

  // 监听蓝牙状态
  private setupBleStateListener() {
    this.manager.onStateChange((state) => {
      console.log('Bluetooth state:', state);
      if (state === State.PoweredOff) {
        this.handleDisconnection();
      }
    }, true);
  }

  // 请求蓝牙权限 (Android)
  async requestPermissions(): Promise<boolean> {
    if (Platform.OS === 'android') {
      const apiLevel = Platform.Version;

      if (apiLevel >= 31) {
        // Android 12+
        const granted = await PermissionsAndroid.requestMultiple([
          PermissionsAndroid.PERMISSIONS.BLUETOOTH_SCAN,
          PermissionsAndroid.PERMISSIONS.BLUETOOTH_CONNECT,
          PermissionsAndroid.PERMISSIONS.ACCESS_FINE_LOCATION,
        ]);

        return (
          granted['android.permission.BLUETOOTH_SCAN'] === PermissionsAndroid.RESULTS.GRANTED &&
          granted['android.permission.BLUETOOTH_CONNECT'] === PermissionsAndroid.RESULTS.GRANTED &&
          granted['android.permission.ACCESS_FINE_LOCATION'] === PermissionsAndroid.RESULTS.GRANTED
        );
      } else {
        // Android 11 及以下
        const granted = await PermissionsAndroid.request(
          PermissionsAndroid.PERMISSIONS.ACCESS_FINE_LOCATION,
        );
        return granted === PermissionsAndroid.RESULTS.GRANTED;
      }
    }
    return true; // iOS 不需要运行时权限
  }

  // 检查蓝牙是否可用
  async isBluetoothEnabled(): Promise<boolean> {
    const state = await this.manager.state();
    return state === State.PoweredOn;
  }

  // 开始扫描设备
  async startScan(): Promise<void> {
    const hasPermission = await this.requestPermissions();
    if (!hasPermission) {
      this.updateScanState({
        isScanning: false,
        devices: [],
        error: '蓝牙权限被拒绝',
      });
      return;
    }

    const isEnabled = await this.isBluetoothEnabled();
    if (!isEnabled) {
      this.updateScanState({
        isScanning: false,
        devices: [],
        error: '请开启蓝牙',
      });
      return;
    }

    // 清空之前的设备列表
    this.updateScanState({
      isScanning: true,
      devices: [],
      error: null,
    });

    // 扫描超时
    setTimeout(() => {
      this.stopScan();
    }, BLUETOOTH_CONSTANTS.SCAN_TIMEOUT);

    // 开始扫描
    this.manager.startDeviceScan(
      [BLUETOOTH_CONSTANTS.SERVICE_UUID],
      {allowDuplicates: false},
      (error, device) => {
        if (error) {
          console.error('Scan error:', error);
          this.updateScanState({
            ...this.scanState,
            isScanning: false,
            error: error.message,
          });
          return;
        }

        if (device && this.isTargetDevice(device)) {
          this.addDiscoveredDevice(device);
        }
      },
    );
  }

  // 停止扫描
  stopScan(): void {
    this.manager.stopDeviceScan();
    this.updateScanState({
      ...this.scanState,
      isScanning: false,
    });
  }

  // 检查是否为目标设备
  private isTargetDevice(device: Device): boolean {
    if (!device.name) return false;
    return device.name.startsWith(BLUETOOTH_CONSTANTS.DEVICE_NAME_PREFIX);
  }

  // 添加发现的设备
  private addDiscoveredDevice(device: Device) {
    const existingIndex = this.scanState.devices.findIndex(d => d.id === device.id);

    const newDevice: BluetoothDevice = {
      id: device.id,
      name: device.name,
      rssi: device.rssi,
      isConnectable: true,
    };

    let updatedDevices: BluetoothDevice[];
    if (existingIndex >= 0) {
      updatedDevices = [...this.scanState.devices];
      updatedDevices[existingIndex] = newDevice;
    } else {
      updatedDevices = [...this.scanState.devices, newDevice];
    }

    // 按信号强度排序
    updatedDevices.sort((a, b) => (b.rssi || -100) - (a.rssi || -100));

    this.updateScanState({
      ...this.scanState,
      devices: updatedDevices,
    });
  }

  // 更新扫描状态
  private updateScanState(state: BluetoothScanState) {
    this.scanState = state;
    this.onScanStateChange?.(state);
  }

  // 连接设备
  async connect(deviceId: string): Promise<boolean> {
    try {
      this.stopScan();

      console.log('Connecting to device:', deviceId);

      // 连接设备
      const device = await this.manager.connectToDevice(deviceId, {
        timeout: BLUETOOTH_CONSTANTS.CONNECTION_TIMEOUT,
      });

      // 发现服务和特征
      await device.discoverAllServicesAndCharacteristics();

      // 获取服务
      const services = await device.services();
      const targetService = services.find(
        s => s.uuid.toLowerCase() === BLUETOOTH_CONSTANTS.SERVICE_UUID.toLowerCase(),
      );

      if (!targetService) {
        throw new Error('未找到目标服务');
      }

      // 获取特征
      const characteristics = await targetService.characteristics();

      this.txCharacteristic = characteristics.find(
        c => c.uuid.toLowerCase() === BLUETOOTH_CONSTANTS.TX_CHARACTERISTIC_UUID.toLowerCase(),
      ) || null;

      this.rxCharacteristic = characteristics.find(
        c => c.uuid.toLowerCase() === BLUETOOTH_CONSTANTS.RX_CHARACTERISTIC_UUID.toLowerCase(),
      ) || null;

      if (!this.txCharacteristic) {
        throw new Error('未找到写入特征');
      }

      // 设置通知监听
      if (this.rxCharacteristic) {
        this.rxCharacteristic.monitor((error, characteristic) => {
          if (error) {
            console.error('Notification error:', error);
            return;
          }
          if (characteristic?.value) {
            this.handleReceivedData(characteristic.value);
          }
        });
      }

      // 监听断开连接
      device.onDisconnected(() => {
        console.log('Device disconnected');
        this.handleDisconnection();
      });

      // 请求 MTU
      try {
        await device.requestMTU(BLUETOOTH_CONSTANTS.MTU_SIZE);
      } catch (e) {
        console.warn('MTU request failed:', e);
      }

      this.connectedDevice = device;
      this.isConnected = true;

      this.onConnectionChange?.(true, {
        id: device.id,
        name: device.name,
        rssi: device.rssi,
        isConnectable: true,
      });

      // 设置为手动模式
      this.setMode(EyeMode.Manual);
      this.startHeartbeat();
      this.startAutoWink();

      return true;
    } catch (error) {
      console.error('Connection error:', error);
      this.handleDisconnection();
      return false;
    }
  }

  // 处理接收到的数据
  private handleReceivedData(base64Data: string) {
    try {
      const data = Buffer.from(base64Data, 'base64').toString('utf-8');
      console.log('Received:', data);

      if (data.startsWith(ProtocolMessages.HEARTBEAT_RESPONSE)) {
        this.handleHeartbeatResponse(data);
      } else if (data.startsWith(ProtocolMessages.SET_MODE_SUCCESS)) {
        this.handleModeSuccess(data);
      }
    } catch (error) {
      console.error('Parse error:', error);
    }
  }

  // 处理心跳响应
  private handleHeartbeatResponse(message: string) {
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

  // 断开连接
  async disconnect(): Promise<void> {
    this.stopHeartbeat();
    this.stopAutoMode();
    this.stopAutoWink();

    if (this.connectedDevice) {
      try {
        await this.sendMessage(ProtocolMessages.DISCONNECT);
        await this.connectedDevice.cancelConnection();
      } catch (error) {
        console.error('Disconnect error:', error);
      }
    }

    this.handleDisconnection();
  }

  // 处理断开连接
  private handleDisconnection() {
    this.connectedDevice = null;
    this.txCharacteristic = null;
    this.rxCharacteristic = null;
    this.isConnected = false;
    this.currentMode = EyeMode.Unconnected;

    this.stopHeartbeat();
    this.stopAutoMode();
    this.stopAutoWink();

    this.onConnectionChange?.(false);
    this.onModeChange?.(EyeMode.Unconnected);
  }

  // 发送消息
  private async sendMessage(message: string): Promise<void> {
    if (!this.txCharacteristic || !this.isConnected) {
      console.warn('Cannot send: not connected');
      return;
    }

    try {
      const base64Data = Buffer.from(message).toString('base64');
      await this.txCharacteristic.writeWithResponse(base64Data);
    } catch (error) {
      console.error('Send error:', error);
    }
  }

  // 启动心跳
  private startHeartbeat() {
    this.stopHeartbeat();
    this.heartbeatTimer = setInterval(() => {
      this.sendMessage(ProtocolMessages.HEARTBEAT_REQUEST);
    }, NETWORK_CONSTANTS.HEARTBEAT_INTERVAL);
  }

  // 停止心跳
  private stopHeartbeat() {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
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

  // 生成随机 PWM
  private generateRandomPWM() {
    const gaussianRandom = () => {
      let u = 0, v = 0;
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
      const interval = 3000 + Math.random() * 4000;
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

  // 执行眨眼
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

  // 播放动作帧
  async playFrames(frames: ActionFrame[]) {
    for (const frame of frames) {
      const range = PWM_CONSTANTS.MAX_VALUE - PWM_CONSTANTS.MIN_VALUE;
      const ch1 = frame.CH1 >= 0 ? PWM_CONSTANTS.MIN_VALUE + frame.CH1 * range : this.currentChannelValues.ch1;
      const ch2 = frame.CH2 >= 0 ? PWM_CONSTANTS.MIN_VALUE + frame.CH2 * range : this.currentChannelValues.ch2;
      const ch3 = frame.CH3 >= 0 ? PWM_CONSTANTS.MIN_VALUE + frame.CH3 * range : this.currentChannelValues.ch3;

      this.updateChannelValues(ch1, ch2, ch3, true, frame.duration);
      await new Promise(resolve => setTimeout(resolve, frame.duration));
    }
  }

  // 获取状态
  getIsConnected(): boolean {
    return this.isConnected;
  }

  getCurrentMode(): EyeMode {
    return this.currentMode;
  }

  getBattery(): number {
    return this.battery;
  }

  getConnectedDevice(): BluetoothDevice | null {
    if (!this.connectedDevice) return null;
    return {
      id: this.connectedDevice.id,
      name: this.connectedDevice.name,
      rssi: this.connectedDevice.rssi,
      isConnectable: true,
    };
  }

  getScanState(): BluetoothScanState {
    return this.scanState;
  }

  // 销毁
  // 发送原始消息 (用于调优指令等)
  sendRawMessage(message: string) {
    this.sendMessage(message);
  }

  destroy() {
    this.disconnect();
    this.manager.destroy();
  }
}

// 单例导出
export const bluetoothClient = new BluetoothClient();
export default BluetoothClient;
