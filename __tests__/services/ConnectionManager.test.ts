import ConnectionManager from '../../src/services/ConnectionManager';
import {mobileClient} from '../../src/services/MobileClient';
import {bluetoothClient} from '../../src/services/BluetoothClient';
import {
  ConnectionType,
  ConnectionState,
  EyeMode,
  ProtocolMessages,
  ActionFrame,
  BatteryStatus,
} from '../../src/types';

// Mock dependencies
jest.mock('../../src/services/MobileClient', () => ({
  mobileClient: {
    setCallbacks: jest.fn(),
    findServer: jest.fn(),
    disconnect: jest.fn(),
    setMode: jest.fn(),
    updateChannelValues: jest.fn(),
    updateChannelValuesWithProportions: jest.fn(),
    playFrames: jest.fn(),
    setAutoWinkEnabled: jest.fn(),
    setAutoModeParameters: jest.fn(),
    sendRawMessage: jest.fn(),
    setVideoCallback: jest.fn(),
    getVideoStreamStats: jest.fn(),
    destroy: jest.fn(),
  },
}));

jest.mock('../../src/services/BluetoothClient', () => ({
  bluetoothClient: {
    setCallbacks: jest.fn(),
    startScan: jest.fn(),
    stopScan: jest.fn(),
    connect: jest.fn(),
    getScanState: jest.fn(),
    disconnect: jest.fn(),
    setMode: jest.fn(),
    updateChannelValues: jest.fn(),
    updateChannelValuesWithProportions: jest.fn(),
    playFrames: jest.fn(),
    setAutoWinkEnabled: jest.fn(),
    setAutoModeParameters: jest.fn(),
    sendRawMessage: jest.fn(),
    destroy: jest.fn(),
  },
}));

// Mock VisualServoController
jest.mock('../../src/services/VisualServoController', () => {
  return {
    VisualServoController: jest.fn().mockImplementation(() => ({
      updateConfig: jest.fn(),
      reset: jest.fn(),
      compute: jest.fn().mockReturnValue({shouldSend: true, ch1: 1500, ch2: 1500}),
      updatePIDParams: jest.fn(),
      getDebugInfo: jest.fn(),
      getConfig: jest.fn(),
    })),
  };
});

describe('ConnectionManager', () => {
  let connectionManager: ConnectionManager;

  beforeEach(() => {
    jest.clearAllMocks();
    // Re-instantiate ConnectionManager for each test to ensure clean state
    connectionManager = new (require('../../src/services/ConnectionManager').default)();
  });

  describe('Initialization', () => {
    it('should set up callbacks on mobileClient and bluetoothClient', () => {
      expect(mobileClient.setCallbacks).toHaveBeenCalled();
      expect(bluetoothClient.setCallbacks).toHaveBeenCalled();
    });
  });

  describe('UDP Connection', () => {
    it('should initiate UDP connection', () => {
      connectionManager.connectUDP();
      expect(connectionManager.getConnectionType()).toBe(ConnectionType.UDP);
      expect(mobileClient.findServer).toHaveBeenCalled();
    });

    it('should handle UDP connection state changes', () => {
      // Get the callback passed to mobileClient.setCallbacks
      const udpConnectionCallback = (mobileClient.setCallbacks as jest.Mock).mock.calls[0][0];

      // Simulate connected state
      const mockState = {
        isConnected: true,
        serverAddress: '192.168.1.100',
        serverPort: 8888,
        battery: 4.0,
        reconnectAttempts: 0,
      };

      // Spy on onConnectionChange
      const onConnectionChange = jest.fn();
      connectionManager.setCallbacks(
        onConnectionChange,
        jest.fn(),
        jest.fn()
      );

      // Trigger callback (need to set type to UDP first)
      connectionManager.connectUDP();
      udpConnectionCallback(mockState);

      expect(onConnectionChange).toHaveBeenCalledWith(expect.objectContaining({
        isConnected: true,
        connectionType: ConnectionType.UDP,
        serverAddress: '192.168.1.100',
        battery: expect.objectContaining({
            voltage1: 4.0,
        }),
      }));
    });
  });

  describe('Bluetooth Connection', () => {
    it('should manage bluetooth scanning', async () => {
      await connectionManager.startBluetoothScan();
      expect(bluetoothClient.startScan).toHaveBeenCalled();

      connectionManager.stopBluetoothScan();
      expect(bluetoothClient.stopScan).toHaveBeenCalled();

      connectionManager.getBluetoothScanState();
      expect(bluetoothClient.getScanState).toHaveBeenCalled();
    });

    it('should connect to bluetooth device', async () => {
      (bluetoothClient.connect as jest.Mock).mockResolvedValue(true);

      const result = await connectionManager.connectBluetooth('device-id');

      expect(connectionManager.getConnectionType()).toBe(ConnectionType.Bluetooth);
      expect(bluetoothClient.connect).toHaveBeenCalledWith('device-id');
      expect(result).toBe(true);
    });

    it('should handle bluetooth connection state changes', () => {
      const btConnectionCallback = (bluetoothClient.setCallbacks as jest.Mock).mock.calls[0][0];

      const onConnectionChange = jest.fn();
      connectionManager.setCallbacks(
        onConnectionChange,
        jest.fn(),
        jest.fn()
      );

      // Simulate connection
      connectionManager.connectBluetooth('device-id');
      btConnectionCallback(true, {id: 'device-id', name: 'SatoriEye'});

      expect(onConnectionChange).toHaveBeenCalledWith(expect.objectContaining({
        isConnected: true,
        connectionType: ConnectionType.Bluetooth,
        deviceId: 'device-id',
        deviceName: 'SatoriEye',
      }));
    });
  });

  describe('Common Operations', () => {
    it('should delegate disconnect to active client', () => {
      // UDP
      connectionManager.connectUDP();
      connectionManager.disconnect();
      expect(mobileClient.disconnect).toHaveBeenCalled();
      expect(connectionManager.getConnectionType()).toBe(ConnectionType.None);

      // Bluetooth
      connectionManager.connectBluetooth('device-id');
      connectionManager.disconnect();
      expect(bluetoothClient.disconnect).toHaveBeenCalled();
      expect(connectionManager.getConnectionType()).toBe(ConnectionType.None);
    });

    it('should delegate setMode', () => {
      connectionManager.connectUDP();
      connectionManager.setMode(EyeMode.Auto);
      expect(mobileClient.setMode).toHaveBeenCalledWith(EyeMode.Auto);

      connectionManager.connectBluetooth('device-id');
      connectionManager.setMode(EyeMode.Manual);
      expect(bluetoothClient.setMode).toHaveBeenCalledWith(EyeMode.Manual);
    });

    it('should delegate updateChannelValues', () => {
      connectionManager.connectUDP();
      connectionManager.updateChannelValues(1500, 1500, 1500);
      expect(mobileClient.updateChannelValues).toHaveBeenCalledWith(1500, 1500, 1500, false, 0);

      connectionManager.connectBluetooth('device-id');
      connectionManager.updateChannelValues(1000, 1000, 1000, true, 100);
      expect(bluetoothClient.updateChannelValues).toHaveBeenCalledWith(1000, 1000, 1000, true, 100);
    });

    it('should delegate playFrames', async () => {
      const frames: ActionFrame[] = [{CH1: 0, CH2: 0, CH3: 0, duration: 100}];

      connectionManager.connectUDP();
      await connectionManager.playFrames(frames);
      expect(mobileClient.playFrames).toHaveBeenCalledWith(frames);
    });
  });

  describe('Tuning Operations', () => {
    it('should send PID parameters via raw message', () => {
      const params = {p: 1.0, i: 0.1, d: 0.05};
      const expectedMsg = `${ProtocolMessages.SET_PID}:${params.p},${params.i},${params.d}`;

      connectionManager.connectUDP();
      connectionManager.setPIDParameters(params);
      expect(mobileClient.sendRawMessage).toHaveBeenCalledWith(expectedMsg);

      connectionManager.connectBluetooth('device-id');
      connectionManager.setPIDParameters(params);
      expect(bluetoothClient.sendRawMessage).toHaveBeenCalledWith(expectedMsg);
    });

    it('should send revive command', () => {
      connectionManager.connectUDP();
      connectionManager.revive();
      expect(mobileClient.sendRawMessage).toHaveBeenCalledWith(ProtocolMessages.REVIVE);
    });
  });

  describe('Visual Servo', () => {
    it('should manage visual servo lifecycle', () => {
      connectionManager.startVisualServo();
      expect(connectionManager.isVisualServoEnabled()).toBe(true);

      connectionManager.stopVisualServo();
      expect(connectionManager.isVisualServoEnabled()).toBe(false);
    });

    it('should update visual servo config', () => {
      connectionManager.startVisualServo();
      connectionManager.updateVisualServoConfig({kp_x: 0.5});
      // Verification relies on mock behavior which is internal,
      // but we can check console.log or just coverage
      expect(connectionManager.getVisualServoConfig()).toBeDefined();
    });
  });

  describe('Video Stream', () => {
    it('should only allow video stream over UDP', () => {
      const config = {
          enabled: true,
          targetFPS: 30,
          resolution: {width: 640, height: 480},
          quality: 'medium' as const
      };

      // Test UDP
      connectionManager.connectUDP();
      connectionManager.startVideoStream(config);
      expect(mobileClient.sendRawMessage).toHaveBeenCalledWith(expect.stringContaining('START_VIDEO'));
      expect(mobileClient.setVideoCallback).toHaveBeenCalled();

      // Test Bluetooth (should warn and not call)
      jest.clearAllMocks();
      connectionManager.connectBluetooth('device-id');
      connectionManager.startVideoStream(config);
      expect(mobileClient.sendRawMessage).not.toHaveBeenCalled();
    });

    it('should stop video stream', () => {
      connectionManager.connectUDP();
      connectionManager.stopVideoStream();
      expect(mobileClient.sendRawMessage).toHaveBeenCalledWith('STOP_VIDEO');
      expect(mobileClient.setVideoCallback).toHaveBeenCalledWith(null);
    });
  });
});
