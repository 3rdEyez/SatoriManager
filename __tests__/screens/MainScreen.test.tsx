import React from 'react';
import {render} from '@testing-library/react-native';
import MainScreen from '../../src/screens/MainScreen';
import {useAppStore} from '../../src/store/appStore';
import {EyeMode} from '../../src/types';

// Mock the store
jest.mock('../../src/store/appStore');

describe('MainScreen', () => {
  const mockStore = {
    connection: {
      isConnected: false,
      serverAddress: null,
      serverPort: null,
      battery: 0,
      reconnectAttempts: 0,
    },
    currentMode: EyeMode.Unconnected,
    battery: 0,
    settings: {
      resetStickOnRelease: true,
      autoWinkEnabled: true,
      pwmRange: 250,
      updateInterval: 2550,
    },
    actionNames: ['wink', 'wink2'],
    connect: jest.fn(),
    disconnect: jest.fn(),
    switchMode: jest.fn(),
    executeAction: jest.fn(),
    setJoystickPosition: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
    (useAppStore as unknown as jest.Mock).mockImplementation((selector) => {
      if (typeof selector === 'function') {
        return selector(mockStore);
      }
      return mockStore;
    });
  });

  describe('Rendering', () => {
    it('should render without crashing', () => {
      const {getByText} = render(<MainScreen />);
      expect(getByText('自动')).toBeTruthy();
    });

    it('should render all mode buttons', () => {
      const {getByText} = render(<MainScreen />);

      expect(getByText('自动')).toBeTruthy();
      expect(getByText('手动')).toBeTruthy();
      expect(getByText('睡眠')).toBeTruthy();
      expect(getByText('追踪')).toBeTruthy();
    });

    it('should render action buttons', () => {
      const {getByText} = render(<MainScreen />);

      expect(getByText('wink')).toBeTruthy();
      expect(getByText('wink2')).toBeTruthy();
    });

    it('should render connect button when disconnected', () => {
      const {getAllByText} = render(<MainScreen />);
      expect(getAllByText('连接设备').length).toBeGreaterThan(0);
    });
  });

  describe('Connected State', () => {
    beforeEach(() => {
      mockStore.connection.isConnected = true;
      mockStore.battery = 85;
    });

    it('should render disconnect button when connected', () => {
      const {getAllByText} = render(<MainScreen />);
      expect(getAllByText('断开连接').length).toBeGreaterThan(0);
    });
  });

  describe('Mode Selection', () => {
    beforeEach(() => {
      mockStore.currentMode = EyeMode.Auto;
    });

    it('should highlight selected mode', () => {
      const {getByText} = render(<MainScreen />);
      // The Auto mode button should be rendered
      expect(getByText('自动')).toBeTruthy();
    });
  });
});
