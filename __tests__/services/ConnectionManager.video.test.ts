import {connectionManager} from '../../src/services/ConnectionManager';
import {mobileClient} from '../../src/services/MobileClient';
import {ConnectionType, VIDEO_STREAM_DEFAULTS} from '../../src/types';

// Mock the client modules
jest.mock('../../src/services/MobileClient', () => ({
  mobileClient: {
    setVideoCallback: jest.fn(),
    sendRawMessage: jest.fn(),
    getVideoStreamStats: jest.fn(() => null),
    setCallbacks: jest.fn(),
    findServer: jest.fn(),
    disconnect: jest.fn(),
    setMode: jest.fn(),
    updateChannelValues: jest.fn(),
    setAutoWinkEnabled: jest.fn(),
    setAutoModeParameters: jest.fn(),
    updateChannelValuesWithProportions: jest.fn(),
    playFrames: jest.fn(),
    getConnectionState: jest.fn(() => ({
      isConnected: false,
      serverAddress: null,
      serverPort: null,
      battery: 0,
      reconnectAttempts: 0,
    })),
    getCurrentMode: jest.fn(() => 0),
    getBattery: jest.fn(() => 0),
    destroy: jest.fn(),
  },
}));

jest.mock('../../src/services/BluetoothClient', () => ({
  bluetoothClient: {
    setCallbacks: jest.fn(),
    startScan: jest.fn(),
    stopScan: jest.fn(),
    connect: jest.fn(),
    disconnect: jest.fn(),
    setMode: jest.fn(),
    updateChannelValues: jest.fn(),
    updateChannelValuesWithProportions: jest.fn(),
    playFrames: jest.fn(),
    getScanState: jest.fn(() => ({
      isScanning: false,
      devices: [],
      error: null,
    })),
    setAutoWinkEnabled: jest.fn(),
    setAutoModeParameters: jest.fn(),
    sendRawMessage: jest.fn(),
    destroy: jest.fn(),
  },
}));

describe('ConnectionManager Video Streaming', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('Video Stream Control Methods', () => {
    it('should have startVideoStream method', () => {
      expect(typeof connectionManager.startVideoStream).toBe('function');
    });

    it('should have stopVideoStream method', () => {
      expect(typeof connectionManager.stopVideoStream).toBe('function');
    });

    it('should have getVideoStreamStats method', () => {
      expect(typeof connectionManager.getVideoStreamStats).toBe('function');
    });

    it('should call startVideoStream without errors', () => {
      expect(() => {
        connectionManager.startVideoStream(VIDEO_STREAM_DEFAULTS);
      }).not.toThrow();
    });

    it('should call stopVideoStream without errors', () => {
      expect(() => {
        connectionManager.stopVideoStream();
      }).not.toThrow();
    });

    it('should call getVideoStreamStats without errors', () => {
      expect(() => {
        connectionManager.getVideoStreamStats();
      }).not.toThrow();
    });
  });

  describe('Video Stream Configuration', () => {
    it('should accept default video stream config', () => {
      expect(() => {
        connectionManager.startVideoStream(VIDEO_STREAM_DEFAULTS);
      }).not.toThrow();
    });

    it('should accept custom FPS configuration', () => {
      const config = {
        ...VIDEO_STREAM_DEFAULTS,
        targetFPS: 15,
      };

      expect(() => {
        connectionManager.startVideoStream(config);
      }).not.toThrow();
    });

    it('should accept custom resolution configuration', () => {
      const config = {
        ...VIDEO_STREAM_DEFAULTS,
        resolution: {width: 320, height: 240},
      };

      expect(() => {
        connectionManager.startVideoStream(config);
      }).not.toThrow();
    });

    it('should accept quality settings', () => {
      const qualities: Array<'low' | 'medium' | 'high'> = ['low', 'medium', 'high'];

      qualities.forEach(quality => {
        const config = {
          ...VIDEO_STREAM_DEFAULTS,
          quality,
        };

        expect(() => {
          connectionManager.startVideoStream(config);
        }).not.toThrow();
      });
    });
  });

  describe('Callback Management', () => {
    it('should allow setting video frame callback', () => {
      const callback = jest.fn();

      expect(() => {
        connectionManager.setCallbacks(
          jest.fn(),
          jest.fn(),
          jest.fn(),
          undefined,
          undefined,
          callback,
        );
      }).not.toThrow();
    });

    it('should allow optional video callback', () => {
      expect(() => {
        connectionManager.setCallbacks(
          jest.fn(),
          jest.fn(),
          jest.fn(),
          undefined,
          undefined,
          undefined,
        );
      }).not.toThrow();
    });

    it('should handle missing video callback', () => {
      expect(() => {
        connectionManager.setCallbacks(jest.fn(), jest.fn(), jest.fn());
      }).not.toThrow();
    });
  });

  describe('Integration with Existing Features', () => {
    it('should work alongside mode changes', () => {
      expect(() => {
        connectionManager.startVideoStream(VIDEO_STREAM_DEFAULTS);
        connectionManager.setMode(2); // Manual mode
      }).not.toThrow();
    });

    it('should work alongside disconnect', () => {
      expect(() => {
        connectionManager.startVideoStream(VIDEO_STREAM_DEFAULTS);
        connectionManager.disconnect();
      }).not.toThrow();
    });

    it('should work alongside channel value updates', () => {
      expect(() => {
        connectionManager.startVideoStream(VIDEO_STREAM_DEFAULTS);
        connectionManager.updateChannelValues(1500, 1500, 1500);
      }).not.toThrow();
    });
  });

  describe('Error Handling', () => {
    it('should handle start video stream with unusual config', () => {
      const config = {
        enabled: true,
        targetFPS: 60,
        resolution: {width: 1920, height: 1080},
        quality: 'high' as const,
      };

      expect(() => {
        connectionManager.startVideoStream(config);
      }).not.toThrow();
    });

    it('should handle stop video stream when not started', () => {
      expect(() => {
        connectionManager.stopVideoStream();
      }).not.toThrow();
    });

    it('should handle multiple start calls', () => {
      expect(() => {
        connectionManager.startVideoStream(VIDEO_STREAM_DEFAULTS);
        connectionManager.startVideoStream(VIDEO_STREAM_DEFAULTS);
      }).not.toThrow();
    });

    it('should handle multiple stop calls', () => {
      expect(() => {
        connectionManager.stopVideoStream();
        connectionManager.stopVideoStream();
      }).not.toThrow();
    });
  });

  describe('Statistics', () => {
    it('should return null or statistics object', () => {
      const stats = connectionManager.getVideoStreamStats();
      expect(stats === null || typeof stats === 'object').toBe(true);
    });

    it('should handle getVideoStreamStats repeatedly', () => {
      expect(() => {
        for (let i = 0; i < 10; i++) {
          connectionManager.getVideoStreamStats();
        }
      }).not.toThrow();
    });
  });

  describe('Connection Type Handling', () => {
    it('should have getConnectionType method', () => {
      expect(typeof connectionManager.getConnectionType).toBe('function');
    });

    it('should return a valid connection type', () => {
      const type = connectionManager.getConnectionType();
      const validTypes = Object.values(ConnectionType);
      expect(validTypes).toContain(type);
    });
  });

  describe('Video Stream Lifecycle', () => {
    it('should handle start-stop cycle', () => {
      expect(() => {
        connectionManager.startVideoStream(VIDEO_STREAM_DEFAULTS);
        connectionManager.stopVideoStream();
      }).not.toThrow();
    });

    it('should handle multiple start-stop cycles', () => {
      expect(() => {
        for (let i = 0; i < 3; i++) {
          connectionManager.startVideoStream(VIDEO_STREAM_DEFAULTS);
          connectionManager.stopVideoStream();
        }
      }).not.toThrow();
    });
  });

  describe('Default Video Stream Configuration', () => {
    it('should have valid default configuration', () => {
      expect(VIDEO_STREAM_DEFAULTS.enabled).toBeDefined();
      expect(VIDEO_STREAM_DEFAULTS.targetFPS).toBeGreaterThan(0);
      expect(VIDEO_STREAM_DEFAULTS.resolution.width).toBeGreaterThan(0);
      expect(VIDEO_STREAM_DEFAULTS.resolution.height).toBeGreaterThan(0);
      expect(['low', 'medium', 'high']).toContain(VIDEO_STREAM_DEFAULTS.quality);
    });

    it('should use default FPS of 30', () => {
      expect(VIDEO_STREAM_DEFAULTS.targetFPS).toBe(30);
    });

    it('should use default resolution of 640x480', () => {
      expect(VIDEO_STREAM_DEFAULTS.resolution.width).toBe(640);
      expect(VIDEO_STREAM_DEFAULTS.resolution.height).toBe(480);
    });

    it('should use default quality of medium', () => {
      expect(VIDEO_STREAM_DEFAULTS.quality).toBe('medium');
    });
  });
});


describe('ConnectionManager Video Streaming', () => {
  let mockVideoCallback: jest.Mock;

  beforeEach(() => {
    jest.clearAllMocks();
    mockVideoCallback = jest.fn();

    // Setup mock implementations
    (mobileClient.setVideoCallback as jest.Mock) = jest.fn();
    (mobileClient.sendRawMessage as jest.Mock) = jest.fn();
    (mobileClient.getVideoStreamStats as jest.Mock) = jest.fn(() => null);
  });

  describe('Video Stream Control - UDP Connection', () => {
    beforeEach(() => {
      // Simulate UDP connection
      const mockConnectionState = {
        isConnected: true,
        connectionType: ConnectionType.UDP,
        serverAddress: '192.168.1.100',
        serverPort: 8888,
        deviceId: null,
        deviceName: null,
        battery: {
          voltage1: 4.1,
          voltage2: 4.1,
          percentage: 95,
          isLow: false,
          isCritical: false,
        },
        reconnectAttempts: 0,
      };

      // Mock the connection state
      jest.spyOn(connectionManager, 'getConnectionState').mockReturnValue(mockConnectionState);
      jest.spyOn(connectionManager, 'getConnectionType').mockReturnValue(ConnectionType.UDP);
    });

    it('should start video stream when connected via UDP', () => {
      const config = VIDEO_STREAM_DEFAULTS;

      connectionManager.startVideoStream(config);

      // Should set video callback on mobileClient
      expect(mobileClient.setVideoCallback).toHaveBeenCalledTimes(1);
      expect(mobileClient.setVideoCallback).toHaveBeenCalledWith(expect.any(Function));

      // Should send START_VIDEO command with config
      expect(mobileClient.sendRawMessage).toHaveBeenCalledTimes(1);
      const expectedMessage = `START_VIDEO:${config.targetFPS}:${config.resolution.width}:${config.resolution.height}:${config.quality}`;
      expect(mobileClient.sendRawMessage).toHaveBeenCalledWith(expectedMessage);
    });

    it('should stop video stream when connected via UDP', () => {
      connectionManager.stopVideoStream();

      // Should send STOP_VIDEO command
      expect(mobileClient.sendRawMessage).toHaveBeenCalledWith('STOP_VIDEO');

      // Should clear video callback
      expect(mobileClient.setVideoCallback).toHaveBeenCalledWith(null);
    });

    it('should forward video frames through callback', () => {
      let capturedCallback: ((frame: VideoFrame) => void) | null = null;

      (mobileClient.setVideoCallback as jest.Mock).mockImplementation((callback) => {
        capturedCallback = callback;
      });

      // Set callbacks on connectionManager
      connectionManager.setCallbacks(
        jest.fn(),
        jest.fn(),
        jest.fn(),
        undefined,
        undefined,
        mockVideoCallback,
      );

      // Start video stream
      connectionManager.startVideoStream(VIDEO_STREAM_DEFAULTS);

      // Simulate receiving a video frame
      const testFrame: VideoFrame = {
        frameId: 1,
        data: new Uint8Array([0xFF, 0xD8, 0xFF, 0xE0]),
        timestamp: Date.now(),
        width: 640,
        height: 480,
      };

      if (capturedCallback) {
        capturedCallback(testFrame);
      }

      // Should forward to registered callback
      expect(mockVideoCallback).toHaveBeenCalledTimes(1);
      expect(mockVideoCallback).toHaveBeenCalledWith(testFrame);
    });

    it('should get video stream statistics', () => {
      const mockStats = {
        droppedFrames: 5,
        receivedFrames: 100,
        avgLatency: 45,
        currentFPS: 28.5,
      };

      (mobileClient.getVideoStreamStats as jest.Mock).mockReturnValue(mockStats);

      const stats = connectionManager.getVideoStreamStats();

      expect(stats).toEqual(mockStats);
      expect(mobileClient.getVideoStreamStats).toHaveBeenCalledTimes(1);
    });
  });

  describe('Video Stream Control - Bluetooth Connection', () => {
    beforeEach(() => {
      // Simulate Bluetooth connection
      const mockConnectionState = {
        isConnected: true,
        connectionType: ConnectionType.Bluetooth,
        serverAddress: null,
        serverPort: null,
        deviceId: 'AA:BB:CC:DD:EE:FF',
        deviceName: 'SatoriEye-001',
        battery: {
          voltage1: 4.0,
          voltage2: 4.0,
          percentage: 90,
          isLow: false,
          isCritical: false,
        },
        reconnectAttempts: 0,
      };

      jest.spyOn(connectionManager, 'getConnectionState').mockReturnValue(mockConnectionState);
      jest.spyOn(connectionManager, 'getConnectionType').mockReturnValue(ConnectionType.Bluetooth);
    });

    it('should not start video stream over Bluetooth', () => {
      connectionManager.startVideoStream(VIDEO_STREAM_DEFAULTS);

      // Should not call mobileClient methods
      expect(mobileClient.setVideoCallback).not.toHaveBeenCalled();
      expect(mobileClient.sendRawMessage).not.toHaveBeenCalled();
    });

    it('should not stop video stream over Bluetooth', () => {
      connectionManager.stopVideoStream();

      // Should not call mobileClient methods
      expect(mobileClient.sendRawMessage).not.toHaveBeenCalled();
      expect(mobileClient.setVideoCallback).not.toHaveBeenCalled();
    });

    it('should return null statistics over Bluetooth', () => {
      const stats = connectionManager.getVideoStreamStats();
      expect(stats).toBeNull();
    });
  });

  describe('Video Stream Control - No Connection', () => {
    beforeEach(() => {
      const mockConnectionState = {
        isConnected: false,
        connectionType: ConnectionType.None,
        serverAddress: null,
        serverPort: null,
        deviceId: null,
        deviceName: null,
        battery: {
          voltage1: 0,
          voltage2: 0,
          percentage: 0,
          isLow: false,
          isCritical: false,
        },
        reconnectAttempts: 0,
      };

      jest.spyOn(connectionManager, 'getConnectionState').mockReturnValue(mockConnectionState);
      jest.spyOn(connectionManager, 'getConnectionType').mockReturnValue(ConnectionType.None);
    });

    it('should not start video stream when not connected', () => {
      connectionManager.startVideoStream(VIDEO_STREAM_DEFAULTS);

      expect(mobileClient.setVideoCallback).not.toHaveBeenCalled();
      expect(mobileClient.sendRawMessage).not.toHaveBeenCalled();
    });

    it('should handle stop video stream gracefully when not connected', () => {
      expect(() => {
        connectionManager.stopVideoStream();
      }).not.toThrow();
    });

    it('should return null statistics when not connected', () => {
      const stats = connectionManager.getVideoStreamStats();
      expect(stats).toBeNull();
    });
  });

  describe('Video Stream Configuration', () => {
    beforeEach(() => {
      jest.spyOn(connectionManager, 'getConnectionType').mockReturnValue(ConnectionType.UDP);
    });

    it('should support custom FPS configuration', () => {
      const config = {
        ...VIDEO_STREAM_DEFAULTS,
        targetFPS: 15,
      };

      connectionManager.startVideoStream(config);

      expect(mobileClient.sendRawMessage).toHaveBeenCalledWith(
        expect.stringContaining('START_VIDEO:15:'),
      );
    });

    it('should support custom resolution configuration', () => {
      const config = {
        ...VIDEO_STREAM_DEFAULTS,
        resolution: {width: 320, height: 240},
      };

      connectionManager.startVideoStream(config);

      expect(mobileClient.sendRawMessage).toHaveBeenCalledWith(
        expect.stringContaining(':320:240:'),
      );
    });

    it('should support quality settings', () => {
      const qualities: Array<'low' | 'medium' | 'high'> = ['low', 'medium', 'high'];

      qualities.forEach(quality => {
        jest.clearAllMocks();

        const config = {
          ...VIDEO_STREAM_DEFAULTS,
          quality,
        };

        connectionManager.startVideoStream(config);

        expect(mobileClient.sendRawMessage).toHaveBeenCalledWith(
          expect.stringContaining(`:${quality}`),
        );
      });
    });

    it('should use default configuration values', () => {
      connectionManager.startVideoStream(VIDEO_STREAM_DEFAULTS);

      const expectedMessage = `START_VIDEO:30:640:480:medium`;
      expect(mobileClient.sendRawMessage).toHaveBeenCalledWith(expectedMessage);
    });
  });

  describe('Callback Management', () => {
    it('should allow setting video frame callback', () => {
      const callback = jest.fn();

      expect(() => {
        connectionManager.setCallbacks(
          jest.fn(),
          jest.fn(),
          jest.fn(),
          undefined,
          undefined,
          callback,
        );
      }).not.toThrow();
    });

    it('should allow optional video callback', () => {
      expect(() => {
        connectionManager.setCallbacks(
          jest.fn(),
          jest.fn(),
          jest.fn(),
          undefined,
          undefined,
          undefined,
        );
      }).not.toThrow();
    });

    it('should handle video frames when callback is not set', () => {
      jest.spyOn(connectionManager, 'getConnectionType').mockReturnValue(ConnectionType.UDP);

      // Don't set video callback
      connectionManager.setCallbacks(jest.fn(), jest.fn(), jest.fn());

      // Should not crash
      expect(() => {
        connectionManager.startVideoStream(VIDEO_STREAM_DEFAULTS);
      }).not.toThrow();
    });
  });

  describe('Integration with Existing Features', () => {
    it('should work alongside mode changes', () => {
      jest.spyOn(connectionManager, 'getConnectionType').mockReturnValue(ConnectionType.UDP);

      connectionManager.startVideoStream(VIDEO_STREAM_DEFAULTS);
      connectionManager.setMode(2); // Manual mode

      // Both should work
      expect(mobileClient.sendRawMessage).toHaveBeenCalled();
    });

    it('should work alongside disconnect', () => {
      jest.spyOn(connectionManager, 'getConnectionType').mockReturnValue(ConnectionType.UDP);

      connectionManager.startVideoStream(VIDEO_STREAM_DEFAULTS);
      connectionManager.disconnect();

      // Should not crash
      expect(() => {
        connectionManager.getVideoStreamStats();
      }).not.toThrow();
    });

    it('should work alongside channel value updates', () => {
      jest.spyOn(connectionManager, 'getConnectionType').mockReturnValue(ConnectionType.UDP);

      connectionManager.startVideoStream(VIDEO_STREAM_DEFAULTS);
      connectionManager.updateChannelValues(1500, 1500, 1500);

      // Both features should coexist
      expect(mobileClient.sendRawMessage).toHaveBeenCalled();
    });
  });

  describe('Error Handling', () => {
    it('should handle start video stream with invalid config gracefully', () => {
      jest.spyOn(connectionManager, 'getConnectionType').mockReturnValue(ConnectionType.UDP);

      const invalidConfig = {
        enabled: true,
        targetFPS: -1,
        resolution: {width: 0, height: 0},
        quality: 'invalid' as any,
      };

      expect(() => {
        connectionManager.startVideoStream(invalidConfig);
      }).not.toThrow();
    });

    it('should handle stop video stream when not started', () => {
      jest.spyOn(connectionManager, 'getConnectionType').mockReturnValue(ConnectionType.UDP);

      expect(() => {
        connectionManager.stopVideoStream();
      }).not.toThrow();
    });

    it('should handle multiple start calls', () => {
      jest.spyOn(connectionManager, 'getConnectionType').mockReturnValue(ConnectionType.UDP);

      connectionManager.startVideoStream(VIDEO_STREAM_DEFAULTS);
      connectionManager.startVideoStream(VIDEO_STREAM_DEFAULTS);

      // Should handle gracefully
      expect(mobileClient.sendRawMessage).toHaveBeenCalledTimes(2);
    });

    it('should handle multiple stop calls', () => {
      jest.spyOn(connectionManager, 'getConnectionType').mockReturnValue(ConnectionType.UDP);

      connectionManager.stopVideoStream();
      connectionManager.stopVideoStream();

      // Should handle gracefully
      expect(mobileClient.sendRawMessage).toHaveBeenCalledTimes(2);
    });
  });

  describe('Statistics Edge Cases', () => {
    it('should handle null statistics gracefully', () => {
      (mobileClient.getVideoStreamStats as jest.Mock).mockReturnValue(null);

      const stats = connectionManager.getVideoStreamStats();
      expect(stats).toBeNull();
    });

    it('should handle statistics with zero values', () => {
      const zeroStats = {
        droppedFrames: 0,
        receivedFrames: 0,
        avgLatency: 0,
        currentFPS: 0,
      };

      (mobileClient.getVideoStreamStats as jest.Mock).mockReturnValue(zeroStats);

      const stats = connectionManager.getVideoStreamStats();
      expect(stats).toEqual(zeroStats);
    });

    it('should handle statistics with extreme values', () => {
      const extremeStats = {
        droppedFrames: 999999,
        receivedFrames: 1000000,
        avgLatency: 5000,
        currentFPS: 120,
      };

      (mobileClient.getVideoStreamStats as jest.Mock).mockReturnValue(extremeStats);

      const stats = connectionManager.getVideoStreamStats();
      expect(stats).toEqual(extremeStats);
    });
  });
});
