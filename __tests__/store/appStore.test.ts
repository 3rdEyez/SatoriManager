import {useAppStore} from '../../src/store/appStore';
import {EyeMode, ConnectionType, HeartbeatStatus} from '../../src/types';

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
    systemStatus: {
      fps: 0,
      cpuTemperature: 0,
      heartbeat: HeartbeatStatus.Lost,
      currentDrawLow: false,
    },
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
  });
});

describe('AppStore', () => {
  describe('Initial State', () => {
    it('should have correct initial connection state', () => {
      const {connection} = useAppStore.getState();
      expect(connection.isConnected).toBe(false);
      expect(connection.serverAddress).toBeNull();
      expect(connection.battery.percentage).toBe(0);
    });

    it('should have correct initial mode', () => {
      const {currentMode} = useAppStore.getState();
      expect(currentMode).toBe(EyeMode.Unconnected);
    });

    it('should have correct initial settings', () => {
      const {settings} = useAppStore.getState();
      expect(settings.resetStickOnRelease).toBe(true);
      expect(settings.autoWinkEnabled).toBe(true);
      expect(settings.pwmRange).toBe(250);
      expect(settings.updateInterval).toBe(2550);
    });

    it('should have correct initial joystick position', () => {
      const {joystickPosition} = useAppStore.getState();
      expect(joystickPosition.x).toBe(0);
      expect(joystickPosition.y).toBe(0);
    });

    it('should have preset action names', () => {
      const {actionNames} = useAppStore.getState();
      expect(actionNames).toContain('wink');
      expect(actionNames).toContain('contempt');
      expect(actionNames).toContain('scan');
      expect(actionNames).toContain('shy');
    });
  });

  describe('Connection State', () => {
    it('should update connection state', () => {
      const {setConnection} = useAppStore.getState();

      setConnection({
        isConnected: true,
        connectionType: ConnectionType.UDP,
        serverAddress: '192.168.1.100',
        serverPort: 8888,
        deviceId: null,
        deviceName: null,
        battery: {
          voltage1: 3.85,
          voltage2: 3.80,
          percentage: 85,
          isLow: false,
          isCritical: false,
        },
        reconnectAttempts: 0,
      });

      const {connection} = useAppStore.getState();
      expect(connection.isConnected).toBe(true);
      expect(connection.serverAddress).toBe('192.168.1.100');
      expect(connection.battery.percentage).toBe(85);
    });
  });

  describe('Mode Management', () => {
    it('should update current mode', () => {
      const {setCurrentMode} = useAppStore.getState();

      setCurrentMode(EyeMode.Auto);
      expect(useAppStore.getState().currentMode).toBe(EyeMode.Auto);

      setCurrentMode(EyeMode.Manual);
      expect(useAppStore.getState().currentMode).toBe(EyeMode.Manual);
    });
  });

  describe('System Status', () => {
    it('should update system status', () => {
      const {setSystemStatus} = useAppStore.getState();

      setSystemStatus({fps: 30, cpuTemperature: 45});
      const {systemStatus} = useAppStore.getState();
      expect(systemStatus.fps).toBe(30);
      expect(systemStatus.cpuTemperature).toBe(45);
    });
  });

  describe('Settings', () => {
    it('should update individual settings', () => {
      const {setSettings} = useAppStore.getState();

      setSettings({resetStickOnRelease: false});
      expect(useAppStore.getState().settings.resetStickOnRelease).toBe(false);
      expect(useAppStore.getState().settings.autoWinkEnabled).toBe(true); // unchanged

      setSettings({pwmRange: 300});
      expect(useAppStore.getState().settings.pwmRange).toBe(300);
    });

    it('should update multiple settings at once', () => {
      const {setSettings} = useAppStore.getState();

      setSettings({
        autoWinkEnabled: false,
        updateInterval: 3000,
      });

      const {settings} = useAppStore.getState();
      expect(settings.autoWinkEnabled).toBe(false);
      expect(settings.updateInterval).toBe(3000);
    });
  });

  describe('Joystick Position', () => {
    it('should update joystick position', () => {
      const {setJoystickPosition} = useAppStore.getState();

      setJoystickPosition({x: 0.5, y: -0.3});

      const {joystickPosition} = useAppStore.getState();
      expect(joystickPosition.x).toBe(0.5);
      expect(joystickPosition.y).toBe(-0.3);
    });

    it('should handle extreme positions', () => {
      const {setJoystickPosition} = useAppStore.getState();

      setJoystickPosition({x: 1, y: 1});
      expect(useAppStore.getState().joystickPosition).toEqual({x: 1, y: 1});

      setJoystickPosition({x: -1, y: -1});
      expect(useAppStore.getState().joystickPosition).toEqual({x: -1, y: -1});
    });
  });

  describe('Eyelid Position', () => {
    it('should update eyelid position', () => {
      const {setEyelidPosition} = useAppStore.getState();

      setEyelidPosition(0.8);
      expect(useAppStore.getState().eyelidPosition).toBe(0.8);

      setEyelidPosition(0.2);
      expect(useAppStore.getState().eyelidPosition).toBe(0.2);
    });
  });

  describe('Pupil Size', () => {
    it('should update pupil size', () => {
      const {setPupilSize} = useAppStore.getState();

      setPupilSize(0.7);
      expect(useAppStore.getState().pupilSize).toBe(0.7);
    });
  });
});
