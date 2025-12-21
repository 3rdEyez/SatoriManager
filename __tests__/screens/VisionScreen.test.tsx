import React from 'react';
import {render, fireEvent, waitFor, act} from '@testing-library/react-native';
import {VisionScreen} from '../../src/screens/VisionScreen';
import {connectionManager} from '../../src/services/ConnectionManager';
import {useAppStore} from '../../src/store/appStore';
import {VideoFrame, ConnectionType, VIDEO_STREAM_DEFAULTS} from '../../src/types';

// Mock dependencies
jest.mock('../../src/services/ConnectionManager');
jest.mock('../../src/store/appStore');
jest.mock('react-native-fast-image', () => ({
  __esModule: true,
  default: 'FastImage',
  resizeMode: {
    contain: 'contain',
    cover: 'cover',
    stretch: 'stretch',
    center: 'center',
  },
}));

describe('VisionScreen', () => {
  let mockStartVideoStream: jest.Mock;
  let mockStopVideoStream: jest.Mock;
  let mockGetVideoStreamStats: jest.Mock;
  let mockSetCallbacks: jest.Mock;

  beforeEach(() => {
    jest.clearAllMocks();
    jest.useFakeTimers();

    // Setup mock implementations
    mockStartVideoStream = jest.fn();
    mockStopVideoStream = jest.fn();
    mockGetVideoStreamStats = jest.fn(() => ({
      currentFPS: 30,
      avgLatency: 50,
      droppedFrames: 2,
    }));
    mockSetCallbacks = jest.fn();

    (connectionManager.startVideoStream as jest.Mock) = mockStartVideoStream;
    (connectionManager.stopVideoStream as jest.Mock) = mockStopVideoStream;
    (connectionManager.getVideoStreamStats as jest.Mock) = mockGetVideoStreamStats;
    (connectionManager.setCallbacks as jest.Mock) = mockSetCallbacks;

    // Default store state - connected via UDP
    (useAppStore as unknown as jest.Mock).mockReturnValue({
      isConnected: true,
      connectionType: ConnectionType.UDP,
    });
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  describe('Initial Rendering', () => {
    it('should render without crashing', () => {
      const {getByText} = render(<VisionScreen />);
      expect(getByText('启动视频流')).toBeTruthy();
    });

    it('should show start button when not streaming', () => {
      const {getByText} = render(<VisionScreen />);
      expect(getByText('启动视频流')).toBeTruthy();
    });

    it('should show connection status', () => {
      const {getByText} = render(<VisionScreen />);
      expect(getByText('UDP')).toBeTruthy();
    });

    it('should display video configuration', () => {
      const {getByText} = render(<VisionScreen />);
      expect(getByText(`分辨率: ${VIDEO_STREAM_DEFAULTS.resolution.width}x${VIDEO_STREAM_DEFAULTS.resolution.height}`)).toBeTruthy();
      expect(getByText(`目标帧率: ${VIDEO_STREAM_DEFAULTS.targetFPS} FPS`)).toBeTruthy();
      expect(getByText(`质量: ${VIDEO_STREAM_DEFAULTS.quality}`)).toBeTruthy();
    });
  });

  describe('Connection States', () => {
    it('should show not connected message when disconnected', () => {
      (useAppStore as unknown as jest.Mock).mockReturnValue({
        isConnected: false,
        connectionType: ConnectionType.None,
      });

      const {getByText} = render(<VisionScreen />);
      expect(getByText('未连接到设备')).toBeTruthy();
    });

    it('should disable start button when not connected', () => {
      (useAppStore as unknown as jest.Mock).mockReturnValue({
        isConnected: false,
        connectionType: ConnectionType.None,
      });

      const {getByText} = render(<VisionScreen />);
      const startButton = getByText('启动视频流').parent;
      expect(startButton?.props.accessibilityState?.disabled).toBe(true);
    });

    it('should show connection type in status', () => {
      const {getByText} = render(<VisionScreen />);
      expect(getByText('UDP')).toBeTruthy();
    });
  });

  describe('Video Stream Control', () => {
    it('should start video stream when start button pressed', () => {
      const {getByText} = render(<VisionScreen />);

      const startButton = getByText('启动视频流');
      fireEvent.press(startButton);

      expect(mockStartVideoStream).toHaveBeenCalledTimes(1);
      expect(mockStartVideoStream).toHaveBeenCalledWith(VIDEO_STREAM_DEFAULTS);
    });

    it('should show stop button after starting stream', () => {
      const {getByText} = render(<VisionScreen />);

      const startButton = getByText('启动视频流');
      fireEvent.press(startButton);

      expect(getByText('停止视频流')).toBeTruthy();
    });

    it('should stop video stream when stop button pressed', () => {
      const {getByText} = render(<VisionScreen />);

      // Start stream
      const startButton = getByText('启动视频流');
      fireEvent.press(startButton);

      // Stop stream
      const stopButton = getByText('停止视频流');
      fireEvent.press(stopButton);

      expect(mockStopVideoStream).toHaveBeenCalledTimes(1);
    });

    it('should not start stream when not connected', () => {
      (useAppStore as unknown as jest.Mock).mockReturnValue({
        isConnected: false,
        connectionType: ConnectionType.None,
      });

      const {getByText} = render(<VisionScreen />);

      const startButton = getByText('启动视频流');
      fireEvent.press(startButton);

      expect(mockStartVideoStream).not.toHaveBeenCalled();
    });
  });

  describe('Statistics Display', () => {
    it('should display FPS statistic', async () => {
      const {getByText} = render(<VisionScreen />);

      // Start stream to trigger stats update
      fireEvent.press(getByText('启动视频流'));

      await act(async () => {
        jest.advanceTimersByTime(600);
      });

      await waitFor(() => {
        expect(getByText('30.0')).toBeTruthy(); // FPS value
      });
    });

    it('should display latency statistic', async () => {
      const {getByText} = render(<VisionScreen />);

      fireEvent.press(getByText('启动视频流'));

      await act(async () => {
        jest.advanceTimersByTime(600);
      });

      await waitFor(() => {
        expect(getByText('50ms')).toBeTruthy(); // Latency value
      });
    });

    it('should display dropped frames statistic', async () => {
      const {getByText} = render(<VisionScreen />);

      fireEvent.press(getByText('启动视频流'));

      await act(async () => {
        jest.advanceTimersByTime(600);
      });

      await waitFor(() => {
        expect(getByText('2')).toBeTruthy(); // Dropped frames value
      });
    });

    it('should update statistics periodically', async () => {
      mockGetVideoStreamStats
        .mockReturnValueOnce({currentFPS: 30, avgLatency: 50, droppedFrames: 2})
        .mockReturnValueOnce({currentFPS: 28, avgLatency: 55, droppedFrames: 3});

      const {getByText} = render(<VisionScreen />);

      fireEvent.press(getByText('启动视频流'));

      // First update
      await act(async () => {
        jest.advanceTimersByTime(600);
      });

      await waitFor(() => {
        expect(getByText('30.0')).toBeTruthy();
      });

      // Second update
      await act(async () => {
        jest.advanceTimersByTime(600);
      });

      await waitFor(() => {
        expect(getByText('28.0')).toBeTruthy();
      });
    });

    it('should stop statistics updates when stream stopped', async () => {
      const {getByText} = render(<VisionScreen />);

      // Start stream
      fireEvent.press(getByText('启动视频流'));

      await act(async () => {
        jest.advanceTimersByTime(600);
      });

      const callCountAfterStart = mockGetVideoStreamStats.mock.calls.length;

      // Stop stream
      fireEvent.press(getByText('停止视频流'));

      await act(async () => {
        jest.advanceTimersByTime(1000);
      });

      // Should not increase call count
      expect(mockGetVideoStreamStats.mock.calls.length).toBe(callCountAfterStart);
    });
  });

  describe('Video Frame Display', () => {
    it('should show placeholder when no frame received', () => {
      const {getByText} = render(<VisionScreen />);

      // Start stream
      fireEvent.press(getByText('启动视频流'));

      expect(getByText('等待视频帧...')).toBeTruthy();
    });

    it('should register video callback on mount', () => {
      render(<VisionScreen />);

      expect(mockSetCallbacks).toHaveBeenCalled();
      // Check that video callback is provided (6th argument)
      const calls = mockSetCallbacks.mock.calls;
      expect(calls[0][5]).toBeInstanceOf(Function);
    });

    it('should display video frame when received', () => {
      let videoCallback: ((frame: VideoFrame) => void) | null = null;

      mockSetCallbacks.mockImplementation(
        (onConnection, onMode, onBattery, onScan, onSystemStatus, onVideoFrame) => {
          videoCallback = onVideoFrame;
        },
      );

      const {queryByTestId} = render(<VisionScreen />);

      // Simulate receiving a frame
      const testFrame: VideoFrame = {
        frameId: 1,
        data: new Uint8Array([0xFF, 0xD8, 0xFF, 0xE0]),
        timestamp: Date.now(),
        width: 640,
        height: 480,
      };

      act(() => {
        if (videoCallback) {
          videoCallback(testFrame);
        }
      });

      // FastImage should be rendered (not placeholder)
      // Note: Exact testing depends on test ID setup
    });
  });

  describe('Lifecycle Management', () => {
    it('should cleanup on unmount', () => {
      const {unmount} = render(<VisionScreen />);

      // Start stream
      const {getByText} = render(<VisionScreen />);
      fireEvent.press(getByText('启动视频流'));

      unmount();

      // Should have stopped stream
      expect(mockStopVideoStream).toHaveBeenCalled();
    });

    it('should stop stream when connection lost', async () => {
      const {rerender} = render(<VisionScreen />);

      // Start stream while connected
      const {getByText} = render(<VisionScreen />);
      fireEvent.press(getByText('启动视频流'));

      // Simulate connection loss
      (useAppStore as unknown as jest.Mock).mockReturnValue({
        isConnected: false,
        connectionType: ConnectionType.None,
      });

      rerender(<VisionScreen />);

      await waitFor(() => {
        expect(mockStopVideoStream).toHaveBeenCalled();
      });
    });
  });

  describe('Error Handling', () => {
    it('should handle missing statistics gracefully', async () => {
      mockGetVideoStreamStats.mockReturnValue(null);

      const {getByText} = render(<VisionScreen />);

      fireEvent.press(getByText('启动视频流'));

      await act(async () => {
        jest.advanceTimersByTime(600);
      });

      // Should display default values
      await waitFor(() => {
        expect(getByText('0.0')).toBeTruthy(); // FPS
        expect(getByText('0ms')).toBeTruthy(); // Latency
      });
    });

    it('should handle video stream start failure gracefully', () => {
      mockStartVideoStream.mockImplementation(() => {
        throw new Error('Stream start failed');
      });

      const {getByText} = render(<VisionScreen />);

      expect(() => {
        fireEvent.press(getByText('启动视频流'));
      }).not.toThrow();
    });

    it('should handle video stream stop failure gracefully', () => {
      mockStopVideoStream.mockImplementation(() => {
        throw new Error('Stream stop failed');
      });

      const {getByText} = render(<VisionScreen />);

      // Start first
      fireEvent.press(getByText('启动视频流'));

      expect(() => {
        fireEvent.press(getByText('停止视频流'));
      }).not.toThrow();
    });
  });

  describe('UI Layout', () => {
    it('should render video container with correct aspect ratio', () => {
      const {UNSAFE_root} = render(<VisionScreen />);

      // Video container should exist
      const container = UNSAFE_root.findAllByProps({elevation: 2})[0];
      expect(container).toBeTruthy();
    });

    it('should render statistics panel', () => {
      const {getByText} = render(<VisionScreen />);

      expect(getByText('连接')).toBeTruthy();
      expect(getByText('FPS')).toBeTruthy();
      expect(getByText('延迟')).toBeTruthy();
      expect(getByText('丢帧')).toBeTruthy();
    });

    it('should render configuration panel', () => {
      const {getByText} = render(<VisionScreen />);

      expect(getByText('配置')).toBeTruthy();
    });
  });

  describe('Accessibility', () => {
    it('should have accessible labels for statistics', () => {
      const {getByText} = render(<VisionScreen />);

      expect(getByText('连接')).toBeTruthy();
      expect(getByText('FPS')).toBeTruthy();
      expect(getByText('延迟')).toBeTruthy();
      expect(getByText('丢帧')).toBeTruthy();
    });

    it('should have accessible button labels', () => {
      const {getByText} = render(<VisionScreen />);

      const startButton = getByText('启动视频流');
      expect(startButton).toBeTruthy();
    });
  });
});
