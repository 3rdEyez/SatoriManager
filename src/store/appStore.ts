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
  VideoStreamState,
  ESP32Device,
  DeviceDiscoveryState,
  MindReadingConfig,
  MindReadingState,
  MindReadingResult,
} from '../types';
import {MIND_READING_DEFAULTS} from '../constants/MindReadingDefaults';
import {connectionManager} from '../services/ConnectionManager';
import {FaceDetectionResult} from '../services/FaceDetector';

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
  // 视觉伺服状态
  visionState: {
    isActive: boolean;
    videoStream: VideoStreamState;
    faceDetection: {
      isEnabled: boolean;
      lastResult: FaceDetectionResult | null;
      avgFPS: number;
      avgLatency: number;
    };
    tracking: {
      isTracking: boolean;
      trackingMode: 'auto' | 'manual' | 'hybrid';
      currentTrackingId: number | null;
    };
  };
  // 设备发现状态
  deviceDiscovery: DeviceDiscoveryState;
  // 读心功能配置
  mindReadingConfig: MindReadingConfig;
  // 读心功能状态
  mindReadingState: MindReadingState;

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

  // 视觉伺服操作
  setVisionActive: (active: boolean) => void;
  updateFaceDetection: (result: FaceDetectionResult) => void;
  updateVideoStreamState: (state: Partial<VideoStreamState>) => void;
  setTrackingMode: (mode: 'auto' | 'manual' | 'hybrid') => void;
  startTracking: () => void;
  stopTracking: () => void;

  // 设备发现操作
  startDeviceDiscovery: () => void;
  stopDeviceDiscovery: () => void;
  selectDevice: (device: ESP32Device) => void;
  updateDiscoveredDevices: (devices: ESP32Device[]) => void;
  startVideoStream: () => void;
  stopVideoStream: () => void;

  // 初始化
  initialize: () => void;

  // 读心功能操作
  setMindReadingConfig: (config: Partial<MindReadingConfig>) => void;
  setMindReadingState: (state: Partial<MindReadingState>) => void;
  startMindReading: () => Promise<void>;
  stopMindReading: () => void;
  updateMindReadingResult: (result: MindReadingResult) => void;
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
  visionState: {
    isActive: false,
    videoStream: {
      isReceiving: false,
      currentFPS: 0,
      droppedFrames: 0,
      avgLatency: 0,
    },
    faceDetection: {
      isEnabled: false,
      lastResult: null,
      avgFPS: 0,
      avgLatency: 0,
    },
    tracking: {
      isTracking: false,
      trackingMode: 'auto',
      currentTrackingId: null,
    },
  },
  deviceDiscovery: {
    isDiscovering: false,
    devices: [],
    selectedDevice: null,
    error: null,
  },

  // 读心功能初始状态
  mindReadingConfig: {...MIND_READING_DEFAULTS},
  mindReadingState: {
    isCapturing: false,
    isAnalyzing: false,
    isServerRunning: false,
    serverUrl: null,
    lastResult: null,
    currentStability: 0,
    currentTrackingId: null,
    error: null,
  },

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

  // ========== 视觉伺服操作 ==========

  // 设置视觉系统激活状态
  setVisionActive: (active) => {
    set((state) => ({
      visionState: {
        ...state.visionState,
        isActive: active,
      },
    }));
  },

  // 更新人脸检测结果
  updateFaceDetection: (result) => {
    set((state) => {
      const fpsHistory = state.visionState.faceDetection.avgFPS;
      const newFPS =
        result.processingTime > 0 ? 1000 / result.processingTime : 0;
      const avgFPS = fpsHistory * 0.7 + newFPS * 0.3; // 指数移动平均

      return {
        visionState: {
          ...state.visionState,
          faceDetection: {
            ...state.visionState.faceDetection,
            lastResult: result,
            avgFPS,
            avgLatency: result.processingTime,
          },
        },
      };
    });
  },

  // 更新视频流状态
  updateVideoStreamState: (streamState) => {
    set((state) => ({
      visionState: {
        ...state.visionState,
        videoStream: {
          ...state.visionState.videoStream,
          ...streamState,
        },
      },
    }));
  },

  // 设置追踪模式
  setTrackingMode: (mode) => {
    set((state) => ({
      visionState: {
        ...state.visionState,
        tracking: {
          ...state.visionState.tracking,
          trackingMode: mode,
        },
      },
    }));
  },

  // 开始追踪
  startTracking: () => {
    connectionManager.startVisualServo();
    set((state) => ({
      visionState: {
        ...state.visionState,
        tracking: {
          ...state.visionState.tracking,
          isTracking: true,
        },
      },
    }));
  },

  // 停止追踪
  stopTracking: () => {
    connectionManager.stopVisualServo();
    set((state) => ({
      visionState: {
        ...state.visionState,
        tracking: {
          ...state.visionState.tracking,
          isTracking: false,
          currentTrackingId: null,
        },
      },
    }));
  },

  // ========== 设备发现操作 ==========

  // 开始设备发现
  startDeviceDiscovery: () => {
    connectionManager.startDeviceDiscovery();
    set((state) => ({
      deviceDiscovery: {
        ...state.deviceDiscovery,
        isDiscovering: true,
        error: null,
      },
    }));
  },

  // 停止设备发现
  stopDeviceDiscovery: () => {
    connectionManager.stopDeviceDiscovery();
    set((state) => ({
      deviceDiscovery: {
        ...state.deviceDiscovery,
        isDiscovering: false,
      },
    }));
  },

  // 选择设备
  selectDevice: (device) => {
    set((state) => ({
      deviceDiscovery: {
        ...state.deviceDiscovery,
        selectedDevice: device,
      },
    }));
  },

  // 更新已发现的设备列表
  updateDiscoveredDevices: (devices) => {
    set((state) => ({
      deviceDiscovery: {
        ...state.deviceDiscovery,
        devices,
      },
    }));
  },

  // 启动视频流
  startVideoStream: () => {
    const {deviceDiscovery} = get();
    if (deviceDiscovery.selectedDevice) {
      connectionManager.startVideoStream(deviceDiscovery.selectedDevice);
      set((state) => ({
        visionState: {
          ...state.visionState,
          videoStream: {
            ...state.visionState.videoStream,
            isReceiving: true,
          },
        },
      }));
    }
  },

  // 停止视频流
  stopVideoStream: () => {
    connectionManager.stopVideoStream();
    set((state) => ({
      visionState: {
        ...state.visionState,
        videoStream: {
          ...state.visionState.videoStream,
          isReceiving: false,
        },
      },
    }));
  },

  // ========== 读心功能操作 ==========

  // 设置读心配置
  setMindReadingConfig: (config) =>
    set((state) => ({
      mindReadingConfig: {...state.mindReadingConfig, ...config},
    })),

  // 设置读心状态
  setMindReadingState: (state) =>
    set((s) => ({
      mindReadingState: {...s.mindReadingState, ...state},
    })),

  // 启动读心功能
  startMindReading: async () => {
    const {mindReadingConfig} = get();
    try {
      // 动态导入以避免循环依赖
      const {getMindReadingService} = require('../services/MindReadingService');
      const service = getMindReadingService();

      await service.initialize(mindReadingConfig);
      await service.start();

      set((s) => ({
        mindReadingState: {
          ...s.mindReadingState,
          isServerRunning: true,
          serverUrl: service.getServerUrl(),
          error: null,
        },
      }));
    } catch (error) {
      console.error('[AppStore] Failed to start mind reading:', error);
      set((s) => ({
        mindReadingState: {
          ...s.mindReadingState,
          error: (error as Error).message,
        },
      }));
      throw error;
    }
  },

  // 停止读心功能
  stopMindReading: () => {
    const {getMindReadingService} = require('../services/MindReadingService');
    const service = getMindReadingService();
    service.stop();

    set((s) => ({
      mindReadingState: {
        ...s.mindReadingState,
        isServerRunning: false,
        serverUrl: null,
        isCapturing: false,
        isAnalyzing: false,
      },
    }));
  },

  // 更新读心结果
  updateMindReadingResult: (result) =>
    set((s) => ({
      mindReadingState: {
        ...s.mindReadingState,
        lastResult: result,
        error: null,
      },
    })),

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
      undefined, // videoFrame callback (handled in VisionScreen)
      (devices) => {
        // Device discovery callback
        get().updateDiscoveredDevices(devices);
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
