import {bluetoothClient} from '../../src/services/BluetoothClient';
import {EyeMode, BLUETOOTH_CONSTANTS} from '../../src/types';

// Reset before each test
beforeEach(() => {
  jest.clearAllMocks();
});

describe('BluetoothClient Service', () => {
  describe('State', () => {
    it('should return initial disconnected state', () => {
      expect(bluetoothClient.getIsConnected()).toBe(false);
    });

    it('should return initial unconnected mode', () => {
      expect(bluetoothClient.getCurrentMode()).toBe(EyeMode.Unconnected);
    });

    it('should return initial zero battery', () => {
      expect(bluetoothClient.getBattery()).toBe(0);
    });

    it('should return null for connected device when not connected', () => {
      expect(bluetoothClient.getConnectedDevice()).toBeNull();
    });
  });

  describe('Scan State', () => {
    it('should return initial scan state', () => {
      const scanState = bluetoothClient.getScanState();
      expect(scanState.isScanning).toBe(false);
      expect(scanState.devices).toEqual([]);
      expect(scanState.error).toBeNull();
    });
  });

  describe('Callbacks', () => {
    it('should set callbacks without error', () => {
      const onConnection = jest.fn();
      const onScan = jest.fn();
      const onMode = jest.fn();
      const onBattery = jest.fn();

      bluetoothClient.setCallbacks(onConnection, onScan, onMode, onBattery);
      // No error should be thrown
    });
  });

  describe('Mode Setting', () => {
    it('should update mode when setMode is called', () => {
      bluetoothClient.setMode(EyeMode.Auto);
      expect(bluetoothClient.getCurrentMode()).toBe(EyeMode.Auto);
    });

    it('should change from Auto to Manual', () => {
      bluetoothClient.setMode(EyeMode.Auto);
      bluetoothClient.setMode(EyeMode.Manual);
      expect(bluetoothClient.getCurrentMode()).toBe(EyeMode.Manual);
    });
  });

  describe('Auto Wink', () => {
    it('should enable auto wink without error', () => {
      bluetoothClient.setAutoWinkEnabled(true);
    });

    it('should disable auto wink without error', () => {
      bluetoothClient.setAutoWinkEnabled(false);
    });
  });

  describe('Auto Mode Parameters', () => {
    it('should update PWM range and interval without error', () => {
      bluetoothClient.setAutoModeParameters(300, 3000);
    });
  });

  describe('Channel Values', () => {
    it('should handle updateChannelValues when not connected', () => {
      // Should not throw
      bluetoothClient.updateChannelValues(1500, 1500, 1500);
    });

    it('should handle smooth PWM values when not connected', () => {
      bluetoothClient.updateChannelValues(1500, 1500, 1500, true, 500);
    });

    it('should convert proportions to PWM values', () => {
      bluetoothClient.updateChannelValuesWithProportions(0.5, 0.5, 0.5);
    });
  });

  describe('Preset Actions', () => {
    it('should play action frames without error', async () => {
      const frames = [
        {CH1: -1, CH2: -1, CH3: 0.0, duration: 50},
        {CH1: -1, CH2: -1, CH3: 1.0, duration: 50},
      ];

      await bluetoothClient.playFrames(frames);
    });
  });
});

describe('Bluetooth Constants', () => {
  it('should have correct service UUID', () => {
    expect(BLUETOOTH_CONSTANTS.SERVICE_UUID).toBe('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
  });

  it('should have correct TX characteristic UUID', () => {
    expect(BLUETOOTH_CONSTANTS.TX_CHARACTERISTIC_UUID).toBe('6e400002-b5a3-f393-e0a9-e50e24dcca9e');
  });

  it('should have correct RX characteristic UUID', () => {
    expect(BLUETOOTH_CONSTANTS.RX_CHARACTERISTIC_UUID).toBe('6e400003-b5a3-f393-e0a9-e50e24dcca9e');
  });

  it('should have correct scan timeout', () => {
    expect(BLUETOOTH_CONSTANTS.SCAN_TIMEOUT).toBe(10000);
  });

  it('should have correct device name prefix', () => {
    expect(BLUETOOTH_CONSTANTS.DEVICE_NAME_PREFIX).toBe('SatoriEye');
  });

  it('should have correct connection timeout', () => {
    expect(BLUETOOTH_CONSTANTS.CONNECTION_TIMEOUT).toBe(10000);
  });

  it('should have correct MTU size', () => {
    expect(BLUETOOTH_CONSTANTS.MTU_SIZE).toBe(512);
  });
});
