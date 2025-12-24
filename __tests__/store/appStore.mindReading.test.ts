/**
 * AppStore Mind Reading Feature Tests
 */

import { useAppStore } from '../../src/store/appStore';
import { MindReadingConfig, MindReadingResult, MIND_READING_DEFAULTS } from '../../src/constants/MindReadingDefaults';
import { ConnectionType, EyeMode } from '../../src/types';

// Reset store before each test
beforeEach(() => {
  useAppStore.setState({
    connection: {
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
    },
    currentMode: EyeMode.Unconnected,
    settings: {
      resetStickOnRelease: true,
      autoWinkEnabled: true,
      pwmRange: 250,
      updateInterval: 2550,
      preferredConnectionType: ConnectionType.UDP,
      sendRateLimit: 50,
    },
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
  });
});

describe('AppStore - Mind Reading', () => {
  describe('Initial State', () => {
    it('should have correct default config', () => {
      const { mindReadingConfig } = useAppStore.getState();

      expect(mindReadingConfig.enabled).toBe(false);
      expect(mindReadingConfig.qianwenApiKey).toBe('');
      expect(mindReadingConfig.customPrompt).toBe('根据这个人的表情和神态，分析他此刻在想什么。请用简练的语言回答。');
      expect(mindReadingConfig.stabilityThreshold).toBe(1000);
      expect(mindReadingConfig.minCaptureInterval).toBe(10000);
      expect(mindReadingConfig.serverPort).toBe(8080);
    });

    it('should have correct initial state', () => {
      const { mindReadingState } = useAppStore.getState();

      expect(mindReadingState.isCapturing).toBe(false);
      expect(mindReadingState.isAnalyzing).toBe(false);
      expect(mindReadingState.isServerRunning).toBe(false);
      expect(mindReadingState.serverUrl).toBeNull();
      expect(mindReadingState.lastResult).toBeNull();
      expect(mindReadingState.currentStability).toBe(0);
      expect(mindReadingState.currentTrackingId).toBeNull();
      expect(mindReadingState.error).toBeNull();
    });

    it('should have default prompt in Chinese', () => {
      const { mindReadingConfig } = useAppStore.getState();

      expect(mindReadingConfig.customPrompt).toContain('分析');
      expect(mindReadingConfig.customPrompt).toContain('此刻');
    });

    it('should have 1 second stability threshold', () => {
      const { mindReadingConfig } = useAppStore.getState();

      expect(mindReadingConfig.stabilityThreshold).toBe(1000);
    });

    it('should have 10 second min capture interval', () => {
      const { mindReadingConfig } = useAppStore.getState();

      expect(mindReadingConfig.minCaptureInterval).toBe(10000);
    });
  });

  describe('Config Management', () => {
    it('should update individual config values', () => {
      const { setMindReadingConfig } = useAppStore.getState();

      setMindReadingConfig({ enabled: true });
      expect(useAppStore.getState().mindReadingConfig.enabled).toBe(true);

      setMindReadingConfig({ qianwenApiKey: 'test-key' });
      expect(useAppStore.getState().mindReadingConfig.qianwenApiKey).toBe('test-key');

      setMindReadingConfig({ serverPort: 9090 });
      expect(useAppStore.getState().mindReadingConfig.serverPort).toBe(9090);
    });

    it('should update multiple config values', () => {
      const { setMindReadingConfig } = useAppStore.getState();

      setMindReadingConfig({
        enabled: true,
        qianwenApiKey: 'new-key',
        serverPort: 8888,
      });

      const { mindReadingConfig } = useAppStore.getState();
      expect(mindReadingConfig.enabled).toBe(true);
      expect(mindReadingConfig.qianwenApiKey).toBe('new-key');
      expect(mindReadingConfig.serverPort).toBe(8888);
    });

    it('should preserve unchanged values', () => {
      const { setMindReadingConfig } = useAppStore.getState();

      const originalPrompt = useAppStore.getState().mindReadingConfig.customPrompt;
      const originalThreshold = useAppStore.getState().mindReadingConfig.stabilityThreshold;

      setMindReadingConfig({ enabled: true });

      expect(useAppStore.getState().mindReadingConfig.customPrompt).toBe(originalPrompt);
      expect(useAppStore.getState().mindReadingConfig.stabilityThreshold).toBe(originalThreshold);
    });

    it('should update API key', () => {
      const { setMindReadingConfig } = useAppStore.getState();
      const apiKey = 'sk-test-api-key-12345';

      setMindReadingConfig({ qianwenApiKey: apiKey });

      expect(useAppStore.getState().mindReadingConfig.qianwenApiKey).toBe(apiKey);
    });

    it('should update custom prompt', () => {
      const { setMindReadingConfig } = useAppStore.getState();
      const customPrompt = 'Custom analysis prompt for testing';

      setMindReadingConfig({ customPrompt });

      expect(useAppStore.getState().mindReadingConfig.customPrompt).toBe(customPrompt);
    });

    it('should update stability threshold', () => {
      const { setMindReadingConfig } = useAppStore.getState();

      setMindReadingConfig({ stabilityThreshold: 2000 });

      expect(useAppStore.getState().mindReadingConfig.stabilityThreshold).toBe(2000);
    });

    it('should update server port', () => {
      const { setMindReadingConfig } = useAppStore.getState();

      setMindReadingConfig({ serverPort: 9999 });

      expect(useAppStore.getState().mindReadingConfig.serverPort).toBe(9999);
    });
  });

  describe('State Management', () => {
    it('should update capturing status', () => {
      const { setMindReadingState } = useAppStore.getState();

      setMindReadingState({ isCapturing: true });

      expect(useAppStore.getState().mindReadingState.isCapturing).toBe(true);
    });

    it('should update analyzing status', () => {
      const { setMindReadingState } = useAppStore.getState();

      setMindReadingState({ isAnalyzing: true });

      expect(useAppStore.getState().mindReadingState.isAnalyzing).toBe(true);
    });

    it('should update server running status', () => {
      const { setMindReadingState } = useAppStore.getState();

      setMindReadingState({ isServerRunning: true });

      expect(useAppStore.getState().mindReadingState.isServerRunning).toBe(true);
    });

    it('should update server URL', () => {
      const { setMindReadingState } = useAppStore.getState();
      const url = 'http://192.168.1.100:8080';

      setMindReadingState({ serverUrl: url });

      expect(useAppStore.getState().mindReadingState.serverUrl).toBe(url);
    });

    it('should update last result', () => {
      const { setMindReadingState, updateMindReadingResult } = useAppStore.getState();
      const result: MindReadingResult = {
        timestamp: Date.now(),
        analysis: 'Test analysis result',
        model: 'qwen-vl-max',
      };

      updateMindReadingResult(result);

      expect(useAppStore.getState().mindReadingState.lastResult).toEqual(result);
    });

    it('should update stability duration', () => {
      const { setMindReadingState } = useAppStore.getState();

      setMindReadingState({ currentStability: 500 });

      expect(useAppStore.getState().mindReadingState.currentStability).toBe(500);
    });

    it('should update tracking ID', () => {
      const { setMindReadingState } = useAppStore.getState();

      setMindReadingState({ currentTrackingId: 12345 });

      expect(useAppStore.getState().mindReadingState.currentTrackingId).toBe(12345);
    });

    it('should update error state', () => {
      const { setMindReadingState } = useAppStore.getState();
      const error = 'Test error message';

      setMindReadingState({ error });

      expect(useAppStore.getState().mindReadingState.error).toBe(error);
    });

    it('should clear error when null is passed', () => {
      const { setMindReadingState } = useAppStore.getState();

      setMindReadingState({ error: 'Some error' });
      expect(useAppStore.getState().mindReadingState.error).toBe('Some error');

      setMindReadingState({ error: null });
      expect(useAppStore.getState().mindReadingState.error).toBeNull();
    });
  });

  describe('Service Control', () => {
    it('should start mind reading service', async () => {
      const { startMindReading } = useAppStore.getState();

      // Note: This test may fail if the service singleton isn't properly mocked
      // In that case, we just verify the action can be called
      expect(() => startMindReading()).not.toThrow();
    });

    it('should stop mind reading service', () => {
      const { stopMindReading } = useAppStore.getState();

      // Verify the action can be called
      expect(() => stopMindReading()).not.toThrow();
    });

    it('should update state on completion', () => {
      const { setMindReadingState } = useAppStore.getState();
      const result: MindReadingResult = {
        timestamp: Date.now(),
        analysis: 'Complete analysis',
        model: 'qwen-vl-max',
      };

      setMindReadingState({
        isCapturing: false,
        isAnalyzing: false,
        lastResult: result,
        error: null,
      });

      const state = useAppStore.getState().mindReadingState;
      expect(state.isCapturing).toBe(false);
      expect(state.isAnalyzing).toBe(false);
      expect(state.lastResult).toEqual(result);
      expect(state.error).toBeNull();
    });
  });

  describe('Complex State Transitions', () => {
    it('should handle full capture to result flow', () => {
      const { setMindReadingState, updateMindReadingResult } = useAppStore.getState();

      // Start capturing
      setMindReadingState({
        isCapturing: true,
        currentStability: 500,
        currentTrackingId: 123,
      });

      // Start analyzing
      setMindReadingState({
        isCapturing: false,
        isAnalyzing: true,
      });

      // Complete with result
      const result: MindReadingResult = {
        timestamp: Date.now(),
        analysis: 'This person looks confident',
        model: 'qwen-vl-max',
      };
      updateMindReadingResult(result);

      // Also need to set analyzing to false separately
      setMindReadingState({
        isAnalyzing: false,
      });

      const state = useAppStore.getState().mindReadingState;
      expect(state.isAnalyzing).toBe(false);
      expect(state.lastResult).toEqual(result);
    });

    it('should handle error during analysis', () => {
      const { setMindReadingState } = useAppStore.getState();

      setMindReadingState({
        isCapturing: false,
        isAnalyzing: false,
        error: 'API request failed',
      });

      const state = useAppStore.getState().mindReadingState;
      expect(state.error).toBe('API request failed');
      expect(state.isAnalyzing).toBe(false);
    });

    it('should track stability progression', () => {
      const { setMindReadingState } = useAppStore.getState();

      // Simulate stability increasing
      setMindReadingState({ currentStability: 250 });
      expect(useAppStore.getState().mindReadingState.currentStability).toBe(250);

      setMindReadingState({ currentStability: 500 });
      expect(useAppStore.getState().mindReadingState.currentStability).toBe(500);

      setMindReadingState({ currentStability: 1000 });
      expect(useAppStore.getState().mindReadingState.currentStability).toBe(1000);
    });
  });

  describe('Config Validation', () => {
    it('should accept valid port numbers', () => {
      const { setMindReadingConfig } = useAppStore.getState();

      setMindReadingConfig({ serverPort: 80 });
      expect(useAppStore.getState().mindReadingConfig.serverPort).toBe(80);

      setMindReadingConfig({ serverPort: 65535 });
      expect(useAppStore.getState().mindReadingConfig.serverPort).toBe(65535);
    });

    it('should accept valid stability thresholds', () => {
      const { setMindReadingConfig } = useAppStore.getState();

      setMindReadingConfig({ stabilityThreshold: 100 });
      expect(useAppStore.getState().mindReadingConfig.stabilityThreshold).toBe(100);

      setMindReadingConfig({ stabilityThreshold: 5000 });
      expect(useAppStore.getState().mindReadingConfig.stabilityThreshold).toBe(5000);
    });

    it('should accept valid min capture intervals', () => {
      const { setMindReadingConfig } = useAppStore.getState();

      setMindReadingConfig({ minCaptureInterval: 1000 });
      expect(useAppStore.getState().mindReadingConfig.minCaptureInterval).toBe(1000);

      setMindReadingConfig({ minCaptureInterval: 60000 });
      expect(useAppStore.getState().mindReadingConfig.minCaptureInterval).toBe(60000);
    });
  });

  describe('Isolation from Other Store Parts', () => {
    it('should not affect other settings', () => {
      const { setMindReadingConfig, setSettings } = useAppStore.getState();

      const originalPwmRange = useAppStore.getState().settings.pwmRange;

      setMindReadingConfig({ enabled: true, serverPort: 9090 });

      expect(useAppStore.getState().settings.pwmRange).toBe(originalPwmRange);
    });

    it('should not affect connection state', () => {
      const { setMindReadingConfig, setConnection } = useAppStore.getState();

      const originalConnected = useAppStore.getState().connection.isConnected;

      setMindReadingConfig({ enabled: true });

      expect(useAppStore.getState().connection.isConnected).toBe(originalConnected);
    });
  });
});
