import {mobileClient} from '../../src/services/MobileClient';
import {EyeMode, NETWORK_CONSTANTS} from '../../src/types';

describe('MobileClient Service', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('Connection State', () => {
    it('should return initial disconnected state', () => {
      const state = mobileClient.getConnectionState();
      expect(state.isConnected).toBe(false);
      expect(state.serverAddress).toBeNull();
    });

    it('should return initial unconnected mode', () => {
      const mode = mobileClient.getCurrentMode();
      expect(mode).toBe(EyeMode.Unconnected);
    });

    it('should return initial zero battery', () => {
      const battery = mobileClient.getBattery();
      expect(battery).toBe(0);
    });
  });

  describe('Disconnect', () => {
    it('should reset mode to unconnected', () => {
      mobileClient.disconnect();
      expect(mobileClient.getCurrentMode()).toBe(EyeMode.Unconnected);
    });

    it('should reset connection state', () => {
      mobileClient.disconnect();
      expect(mobileClient.getConnectionState().isConnected).toBe(false);
    });
  });

  describe('Mode Setting', () => {
    it('should update mode when setMode is called', () => {
      mobileClient.setMode(EyeMode.Auto);
      expect(mobileClient.getCurrentMode()).toBe(EyeMode.Auto);
    });

    it('should change from Auto to Manual', () => {
      mobileClient.setMode(EyeMode.Auto);
      mobileClient.setMode(EyeMode.Manual);
      expect(mobileClient.getCurrentMode()).toBe(EyeMode.Manual);
    });
  });

  describe('Auto Wink', () => {
    it('should enable auto wink', () => {
      mobileClient.setAutoWinkEnabled(true);
      // No error should be thrown
    });

    it('should disable auto wink', () => {
      mobileClient.setAutoWinkEnabled(false);
      // No error should be thrown
    });
  });

  describe('Auto Mode Parameters', () => {
    it('should update PWM range and interval', () => {
      mobileClient.setAutoModeParameters(300, 3000);
      // Parameters should be updated internally
    });
  });

  describe('Channel Values', () => {
    it('should handle PWM values without error', () => {
      mobileClient.updateChannelValues(1500, 1500, 1500);
      // Should not throw
    });

    it('should handle smooth PWM values without error', () => {
      mobileClient.updateChannelValues(1500, 1500, 1500, true, 500);
      // Should not throw
    });

    it('should handle proportions without error', () => {
      mobileClient.updateChannelValuesWithProportions(0.5, 0.5, 0.5);
      // Should not throw
    });
  });

  describe('Preset Actions', () => {
    it('should play action frames', async () => {
      const frames = [
        {CH1: -1, CH2: -1, CH3: 0.0, duration: 50},
        {CH1: -1, CH2: -1, CH3: 1.0, duration: 50},
      ];

      await mobileClient.playFrames(frames);
      // Should not throw
    });
  });

  describe('Callbacks', () => {
    it('should set callbacks without error', () => {
      const onConnection = jest.fn();
      const onMode = jest.fn();
      const onBattery = jest.fn();

      mobileClient.setCallbacks(onConnection, onMode, onBattery);
      // No error should be thrown
    });
  });
});

describe('Network Constants', () => {
  it('should have correct server port', () => {
    expect(NETWORK_CONSTANTS.SERVER_PORT).toBe(8888);
  });

  it('should have correct broadcast address', () => {
    expect(NETWORK_CONSTANTS.BROADCAST_ADDRESS).toBe('224.0.0.1');
  });

  it('should have correct localhost address', () => {
    expect(NETWORK_CONSTANTS.LOCALHOST).toBe('127.0.0.1');
  });
});
