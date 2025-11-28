import React from 'react';
import {render} from '@testing-library/react-native';
import SettingScreen from '../../src/screens/SettingScreen';
import {useAppStore} from '../../src/store/appStore';

// Mock the store
jest.mock('../../src/store/appStore');

describe('SettingScreen', () => {
  const mockStore = {
    settings: {
      resetStickOnRelease: true,
      autoWinkEnabled: true,
      pwmRange: 250,
      updateInterval: 2550,
    },
    setSettings: jest.fn(),
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
      const {getByText} = render(<SettingScreen />);
      expect(getByText('设置')).toBeTruthy();
    });

    it('should render PWM range setting', () => {
      const {getByText} = render(<SettingScreen />);
      expect(getByText('PWM 变化范围')).toBeTruthy();
    });

    it('should render update interval setting', () => {
      const {getByText} = render(<SettingScreen />);
      expect(getByText('更新间隔')).toBeTruthy();
    });

    it('should render version info', () => {
      const {getByText} = render(<SettingScreen />);
      expect(getByText('SatoriManager v1.0.0')).toBeTruthy();
    });
  });

  describe('Setting Values', () => {
    it('should display current PWM range', () => {
      const {getByText} = render(<SettingScreen />);
      expect(getByText('±250')).toBeTruthy();
    });
  });
});
