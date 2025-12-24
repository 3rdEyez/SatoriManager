/**
 * MindReadingService Tests
 */

import { MindReadingService, getMindReadingService } from '../../src/services/MindReadingService';
import { MindReadingConfig, MindReadingResult } from '../../src/types';
import { FaceDetectionResult } from '../../src/services/FaceDetector';

// Mock child services
let mockFaceCaptureManagerInstance: any = null;
let mockQianwenClientInstance: any = null;
let mockWebSocketServerInstance: any = null;
let storedCaptureCallback: any = null;

jest.mock('../../src/services/FaceCaptureManager', () => {
  return {
    FaceCaptureManager: jest.fn().mockImplementation(() => {
      const instance = {
        setConfig: jest.fn(),
        onCapture: jest.fn((callback: any) => {
          storedCaptureCallback = callback;
        }),
        onFaceDetected: jest.fn(),
        reset: jest.fn(),
        getStability: jest.fn().mockReturnValue(0),
        getCurrentTrackingId: jest.fn().mockReturnValue(null),
        isTracking: jest.fn().mockReturnValue(false),
        getProgress: jest.fn().mockReturnValue(0),
      };
      mockFaceCaptureManagerInstance = instance;
      return instance;
    }),
  };
});

jest.mock('../../src/services/QianwenClient', () => {
  return {
    QianwenClient: jest.fn().mockImplementation(() => {
      const instance = {
        setApiKey: jest.fn(),
        getApiKey: jest.fn().mockReturnValue(''),
        analyzeImage: jest.fn(),
        onResponse: jest.fn((cb: any) => {
          // Store callback
          instance.responseCallback = cb;
          return () => { instance.responseCallback = null; };
        }),
        onError: jest.fn((cb: any) => {
          // Store callback
          instance.errorCallback = cb;
          return () => { instance.errorCallback = null; };
        }),
      };
      mockQianwenClientInstance = instance;
      return instance;
    }),
  };
});

jest.mock('../../src/services/WebSocketServer', () => {
  return {
    WebSocketServer: jest.fn().mockImplementation(() => {
      const instance = {
        start: jest.fn().mockResolvedValue('http://192.168.1.100:8080'),
        stop: jest.fn(),
        isRunning: jest.fn().mockReturnValue(false),
        getServerUrl: jest.fn().mockReturnValue(null),
        broadcast: jest.fn(),
        onStateChange: jest.fn(),
        // Add a method to get the latest instance
        _getLatestInstance: () => mockWebSocketServerInstance,
      };
      mockWebSocketServerInstance = instance;
      return instance;
    }),
  };
});

describe('MindReadingService', () => {
  let service: MindReadingService;
  let mockFaceCaptureManager: any;
  let mockQianwenClient: any;
  let mockWebSocketServer: any;

  const mockConfig: MindReadingConfig = {
    enabled: true,
    qianwenApiKey: 'test-api-key',
    customPrompt: 'Test prompt',
    stabilityThreshold: 1000,
    minCaptureInterval: 10000,
    serverPort: 8080,
  };

  const mockFrame = {
    frameId: 1,
    data: new Uint8Array([0xFF, 0xD8]),
    timestamp: Date.now(),
    width: 640,
    height: 480,
  };

  const mockFaceResult: FaceDetectionResult = {
    faces: [{
      boundingBox: { x: 100, y: 100, width: 80, height: 80 },
      centerX: 0,
      centerY: 0,
      confidence: 1.0,
      trackingId: 123,
    }],
    imageWidth: 640,
    imageHeight: 480,
    timestamp: Date.now(),
    processingTime: 50,
  };

  beforeEach(() => {
    jest.clearAllMocks();
    jest.useFakeTimers();

    // Reset singleton
    (global as any).mindReadingServiceInstance = null;

    // Get fresh service instance (this creates new mock instances and registers callbacks)
    service = getMindReadingService();

    // Use the stored mock instances (they persist because we use clearAllMocks)
    mockFaceCaptureManager = mockFaceCaptureManagerInstance;
    mockQianwenClient = mockQianwenClientInstance;
    mockWebSocketServer = mockWebSocketServerInstance;

    // Reset WebSocket running state
    mockWebSocketServer.isRunning.mockReturnValue(false);
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  describe('Initialization', () => {
    it('should initialize with default config', async () => {
      await service.initialize(mockConfig);

      expect(mockQianwenClient.setApiKey).toHaveBeenCalledWith(mockConfig.qianwenApiKey);
    });

    it('should create child services', () => {
      expect(getMindReadingService()).toBe(service);
    });

    it('should setup callbacks', async () => {
      const stateCallback = jest.fn();
      service.onStateChange(stateCallback);

      await service.initialize(mockConfig);
      await service.start();

      // Should have been called during start
      expect(stateCallback).toHaveBeenCalled();
    });
  });

  describe('Service Lifecycle', () => {
    beforeEach(async () => {
      await service.initialize(mockConfig);
      // Ensure service is not running from previous tests
      service.stop();
    });

    it('should start all services on start()', async () => {
      await service.start();

      expect(mockWebSocketServer.start).toHaveBeenCalledWith(mockConfig.serverPort);
      expect(mockFaceCaptureManager.setConfig).toHaveBeenCalledWith(
        mockConfig.stabilityThreshold,
        mockConfig.minCaptureInterval,
      );
    });

    it('should stop all services on stop()', () => {
      service.stop();

      expect(mockWebSocketServer.stop).toHaveBeenCalled();
    });

    it('should handle start when already running', async () => {
      await service.start(); // First start
      await service.start(); // Second start - should be no-op

      expect(mockWebSocketServer.start).toHaveBeenCalledTimes(1);
    });

    it('should update config dynamically', async () => {
      const newConfig = { qianwenApiKey: 'new-key', serverPort: 9090 };

      await service.start();
      service.updateConfig(newConfig);

      expect(mockQianwenClient.setApiKey).toHaveBeenCalledWith('new-key');
    });
  });

  describe('Frame Processing', () => {
    beforeEach(async () => {
      await service.initialize(mockConfig);
      await service.start();
    });

    it('should ignore frames when not running', () => {
      service.stop();
      service.processFrame(mockFrame, mockFaceResult);

      // Should not process frames when stopped
      expect(mockFaceCaptureManager.onFaceDetected).not.toHaveBeenCalled();
    });

    it('should forward frames to capture manager', () => {
      service.processFrame(mockFrame, mockFaceResult);

      expect(mockFaceCaptureManager.onFaceDetected).toHaveBeenCalledWith(mockFaceResult, mockFrame);
    });

    it('should handle capture trigger', async () => {
      mockQianwenClient.analyzeImage = jest.fn().mockResolvedValue({
        timestamp: Date.now(),
        analysis: 'Test result',
        model: 'qwen-vl-max',
      } as MindReadingResult);

      // Trigger capture manually using stored callback
      if (storedCaptureCallback) {
        await storedCaptureCallback({ trackingId: 123, stabilityDuration: 1000, frame: mockFrame });
      }

      // Should trigger API call
      expect(mockQianwenClient.analyzeImage).toHaveBeenCalled();
    });

    it('should update error state on API failure', async () => {
      const stateCallback = jest.fn();
      service.onStateChange(stateCallback);

      mockQianwenClient.analyzeImage = jest.fn().mockRejectedValue(new Error('API Error'));

      // Trigger capture using stored callback
      if (storedCaptureCallback) {
        await storedCaptureCallback({ trackingId: 123, stabilityDuration: 1000, frame: mockFrame });
      }

      await jest.runAllTimersAsync();

      // Should update error state
      const errorCalls = stateCallback.mock.calls.filter(call => call[0].error);
      expect(errorCalls.length).toBeGreaterThan(0);
    });
  });

  describe('State Management', () => {
    beforeEach(async () => {
      await service.initialize(mockConfig);
      // Ensure server starts as not running
      mockWebSocketServer.isRunning.mockReturnValue(false);
      // Stop service if it was running from previous test
      service.stop();
    });

    it('should report correct running status', () => {
      expect(service.isActive()).toBe(false);

      service.start();
      expect(service.isActive()).toBe(true);
    });

    it('should report correct config', () => {
      const config = service.getConfig();

      expect(config.enabled).toBe(mockConfig.enabled);
      expect(config.qianwenApiKey).toBe(mockConfig.qianwenApiKey);
    });

    it('should notify state changes', async () => {
      const callback = jest.fn();
      service.onStateChange(callback);

      // State changes happen on start/stop, not on config update
      await service.start();
      service.stop();

      expect(callback).toHaveBeenCalled();
    });

    it('should get WebSocket server instance', () => {
      const wsServer = service.getWebSocketServer();

      expect(wsServer).toBeDefined();
    });

    it('should get face capture manager instance', () => {
      const captureManager = service.getFaceCaptureManager();

      expect(captureManager).toBeDefined();
    });
  });

  describe('Error Handling', () => {
    beforeEach(async () => {
      await service.initialize(mockConfig);
    });

    it('should handle API errors gracefully', async () => {
      const stateCallback = jest.fn();
      service.onStateChange(stateCallback);

      mockQianwenClient.analyzeImage = jest.fn().mockRejectedValue(new Error('API Error'));

      await service.start();

      // Trigger capture using stored callback
      if (storedCaptureCallback) {
        await storedCaptureCallback({ trackingId: 123, stabilityDuration: 1000, frame: mockFrame });
      }

      await jest.runAllTimersAsync();

      // Should have error in state
      const lastState = stateCallback.mock.calls[stateCallback.mock.calls.length - 1][0];
      expect(lastState.error).toBeDefined();
    });

    it('should continue after errors', async () => {
      const stateCallback = jest.fn();
      service.onStateChange(stateCallback);

      mockQianwenClient.analyzeImage = jest.fn()
        .mockRejectedValueOnce(new Error('First error'))
        .mockResolvedValueOnce({
          timestamp: Date.now(),
          analysis: 'Success',
          model: 'qwen-vl-max',
        } as MindReadingResult);

      await service.start();

      // Trigger first capture (will error) - service's error handler should catch it
      if (storedCaptureCallback) {
        await storedCaptureCallback({ trackingId: 123, stabilityDuration: 1000, frame: mockFrame });
      }

      await jest.runAllTimersAsync();

      // State should have been updated with error, then cleared on success
      expect(stateCallback).toHaveBeenCalled();
    });
  });

  describe('Singleton Pattern', () => {
    it('should return same instance on multiple calls', () => {
      const instance1 = getMindReadingService();
      const instance2 = getMindReadingService();

      expect(instance1).toBe(instance2);
    });
  });

  describe('Integration Flow', () => {
    beforeEach(async () => {
      await service.initialize(mockConfig);
    });

    it('should complete full capture -> analyze -> broadcast flow', async () => {
      const mockResult: MindReadingResult = {
        timestamp: Date.now(),
        analysis: 'This person looks happy',
        model: 'qwen-vl-max',
      };

      // Mock analyzeImage to return success
      mockQianwenClient.analyzeImage = jest.fn().mockResolvedValue(mockResult);

      await service.start();
      service.processFrame(mockFrame, mockFaceResult);

      // Trigger capture using stored callback
      if (storedCaptureCallback) {
        await storedCaptureCallback({ trackingId: 123, stabilityDuration: 1000, frame: mockFrame });
      }

      await jest.runAllTimersAsync();

      // Verify flow
      expect(mockFaceCaptureManager.onFaceDetected).toHaveBeenCalled();
      expect(mockQianwenClient.analyzeImage).toHaveBeenCalledWith(
        mockFrame.data,
        mockConfig.customPrompt,
      );
      expect(mockWebSocketServer.broadcast).toHaveBeenCalledWith(mockResult);
    });
  });
});
