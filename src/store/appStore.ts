import {create} from 'zustand';
import {
  EyeMode,
  ConnectionType,
  ConnectionState,
  AppSettings,
  JoystickPosition,
  PresetActions,
  BluetoothDevice,
  BluetoothScanState,
  SystemStatus,
  TuningParameters,
  PIDParameters,
  FilterParameters,
  HeartbeatStatus,
  ActionMacros,
  PID_DEFAULTS,
  FILTER_DEFAULTS,
  BatteryStatus,
} from '../types';
import {connectionManager} from '../services/ConnectionManager';

// 默认电池状态
const defaultBatteryStatus: BatteryStatus = {
  voltage1: 0,
  voltage2: 0,
  percentage: 0,
  isLow: false,
  isCritical: false,
};

// 默认系统状态
const defaultSystemStatus: SystemStatus = {
  fps: 0,
  cpuTemperature: 0,
  heartbeat: HeartbeatStatus.Lost,
  currentDrawLow: false,
};

// 默认调优参数
const defaultTuningParameters: TuningParameters = {
  pid: {...PID_DEFAULTS},
  filter: {...FILTER_DEFAULTS},
  calibration: {
    centerPitch: 1500,
    centerYaw: 1500,
    isCalibrated: false,
  },
};

interface AppState {
  // 连接状态
  connection: ConnectionState;
  // 当前模式
  currentMode: EyeMode;
  // 系统状态
  systemStatus: SystemStatus;
  // 设置
  settings: AppSettings;
  // 摇杆位置
  joystickPosition: JoystickPosition;
  // 眼皮位置 (0-1)
  eyelidPosition: number;
  // 瞳孔大小 (0-1)
  pupilSize: number;
  // 预设动作列表
  actionNames: string[];
  // 蓝牙扫描状态
  bluetoothScan: BluetoothScanState;
  // 调优参数
  tuningParameters: TuningParameters;

  // Actions
  setConnection: (state: ConnectionState) => void;
  setCurrentMode: (mode: EyeMode) => void;
  setSystemStatus: (status: Partial<SystemStatus>) => void;
  setSettings: (settings: Partial<AppSettings>) => void;
  setJoystickPosition: (position: JoystickPosition) => void;
  setEyelidPosition: (position: number) => void;
  setPupilSize: (size: number) => void;
  setBluetoothScan: (state: BluetoothScanState) => void;

  // 连接操作
  connectUDP: () => void;
  startBluetoothScan: () => Promise<void>;
  stopBluetoothScan: () => void;
  connectBluetooth: (deviceId: string) => Promise<boolean>;
  disconnect: () => void;

  // 控制操作
  switchMode: (mode: EyeMode) => void;
  executeAction: (actionName: string) => void;

  // 调优操作
  applyPID: (params: PIDParameters) => void;
  applyFilter: (params: FilterParameters) => void;
  calibrateCenter: () => void;
  revive: () => void;

  // 初始化
  initialize: () => void;
}

export const useAppStore = create<AppState>((set, get) => ({
  // 初始状态
  connection: {
    isConnected: false,
    connectionType: ConnectionType.None,
    serverAddress: null,
    serverPort: null,
    deviceId: null,
    deviceName: null,
    battery: {...defaultBatteryStatus},
    reconnectAttempts: 0,
  },
  currentMode: EyeMode.Unconnected,
  systemStatus: {...defaultSystemStatus},
  settings: {
    resetStickOnRelease: true,
    autoWinkEnabled: true,
    pwmRange: 250,
    updateInterval: 2550,
    preferredConnectionType: ConnectionType.UDP,
    sendRateLimit: 50,
  },
  joystickPosition: {x: 0, y: 0},
  eyelidPosition: 0.5,
  pupilSize: 0.5,
  actionNames: Object.keys(ActionMacros),
  bluetoothScan: {
    isScanning: false,
    devices: [],
    error: null,
  },
  tuningParameters: {...defaultTuningParameters},

  // 设置连接状态
  setConnection: (connection) => set({connection}),

  // 设置当前模式
  setCurrentMode: (currentMode) => set({currentMode}),

  // 设置系统状态
  setSystemStatus: (status) =>
    set((state) => ({
      systemStatus: {...state.systemStatus, ...status},
    })),

  // 更新设置
  setSettings: (newSettings) =>
    set((state) => ({
      settings: {...state.settings, ...newSettings},
    })),

  // 设置摇杆位置
  setJoystickPosition: (position) => {
    set({joystickPosition: position});
    // 转换为 PWM 比例值并发送
    const ch1Prop = (position.x + 1) / 2; // -1~1 转换为 0~1
    const ch2Prop = (position.y + 1) / 2;
    connectionManager.updateChannelValuesWithProportions(ch1Prop, ch2Prop, -1);
  },

  // 设置眼皮位置
  setEyelidPosition: (position) => {
    set({eyelidPosition: position});
    connectionManager.updateChannelValuesWithProportions(-1, -1, position);
  },

  // 设置瞳孔大小
  setPupilSize: (size) => {
    set({pupilSize: size});
    // 预留功能
  },

  // 设置蓝牙扫描状态
  setBluetoothScan: (bluetoothScan) => set({bluetoothScan}),

  // 通过 UDP 连接
  connectUDP: () => {
    connectionManager.connectUDP();
  },

  // 开始蓝牙扫描
  startBluetoothScan: async () => {
    await connectionManager.startBluetoothScan();
  },

  // 停止蓝牙扫描
  stopBluetoothScan: () => {
    connectionManager.stopBluetoothScan();
  },

  // 通过蓝牙连接
  connectBluetooth: async (deviceId: string) => {
    return await connectionManager.connectBluetooth(deviceId);
  },

  // 断开连接
  disconnect: () => {
    connectionManager.disconnect();
  },

  // 切换模式
  switchMode: (mode) => {
    connectionManager.setMode(mode);
  },

  // 执行预设动作
  executeAction: (actionName) => {
    const macro = ActionMacros[actionName];
    if (macro) {
      connectionManager.playFrames(macro.frames);
    }
  },

  // 应用 PID 参数
  applyPID: (params) => {
    set((state) => ({
      tuningParameters: {
        ...state.tuningParameters,
        pid: {...params},
      },
    }));
    connectionManager.setPIDParameters(params);
  },

  // 应用滤波器参数
  applyFilter: (params) => {
    set((state) => ({
      tuningParameters: {
        ...state.tuningParameters,
        filter: {...params},
      },
    }));
    connectionManager.setFilterParameters(params);
  },

  // 校准中心位置
  calibrateCenter: () => {
    connectionManager.calibrateCenter();
    set((state) => ({
      tuningParameters: {
        ...state.tuningParameters,
        calibration: {
          ...state.tuningParameters.calibration,
          isCalibrated: true,
        },
      },
    }));
  },

  // 电击复苏
  revive: () => {
    connectionManager.revive();
    set((state) => ({
      systemStatus: {
        ...state.systemStatus,
        heartbeat: HeartbeatStatus.Reviving,
      },
    }));
  },

  // 初始化
  initialize: () => {
    const {settings} = get();

    // 设置回调
    connectionManager.setCallbacks(
      (connection) => {
        set({connection});
      },
      (mode) => {
        set({currentMode: mode});
      },
      (battery) => {
        set((state) => ({
          connection: {
            ...state.connection,
            battery,
          },
        }));
      },
      (scanState) => {
        set({bluetoothScan: scanState});
      },
      (systemStatus) => {
        set({systemStatus});
      },
    );

    // 应用设置
    connectionManager.setAutoWinkEnabled(settings.autoWinkEnabled);
    connectionManager.setAutoModeParameters(settings.pwmRange, settings.updateInterval);
  },
}));

// 设置变化时同步到 ConnectionManager
useAppStore.subscribe((state, prevState) => {
  if (state.settings.autoWinkEnabled !== prevState.settings.autoWinkEnabled) {
    connectionManager.setAutoWinkEnabled(state.settings.autoWinkEnabled);
  }
  if (
    state.settings.pwmRange !== prevState.settings.pwmRange ||
    state.settings.updateInterval !== prevState.settings.updateInterval
  ) {
    connectionManager.setAutoModeParameters(state.settings.pwmRange, state.settings.updateInterval);
  }
});
