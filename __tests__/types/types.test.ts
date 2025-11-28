import {
  EyeMode,
  ProtocolMessages,
  PWM_CONSTANTS,
  NETWORK_CONSTANTS,
  MODE_NAMES,
} from '../../src/types';

describe('Types and Constants', () => {
  describe('EyeMode enum', () => {
    it('should have correct values', () => {
      expect(EyeMode.Unconnected).toBe(0);
      expect(EyeMode.Auto).toBe(1);
      expect(EyeMode.Manual).toBe(2);
      expect(EyeMode.Sleep).toBe(3);
      expect(EyeMode.FacialRecognition).toBe(4);
    });

    it('should have 5 modes', () => {
      const modes = Object.values(EyeMode).filter(v => typeof v === 'number');
      expect(modes.length).toBe(5);
    });
  });

  describe('ProtocolMessages', () => {
    it('should have correct discovery messages', () => {
      expect(ProtocolMessages.DISCOVERY_REQUEST).toBe('SatoriEye_DISCOVERY_REQUEST');
      expect(ProtocolMessages.DISCOVERY_RESPONSE).toBe('SatoriEye_DISCOVERY_RESPONSE');
    });

    it('should have correct heartbeat messages', () => {
      expect(ProtocolMessages.HEARTBEAT_REQUEST).toBe('SatoriEye_HEARTBEAT_REQUEST');
      expect(ProtocolMessages.HEARTBEAT_RESPONSE).toBe('SatoriEye_HEARTBEAT_RESPONSE');
    });

    it('should have correct mode messages', () => {
      expect(ProtocolMessages.SET_MODE).toBe('SET_MODE');
      expect(ProtocolMessages.SET_MODE_SUCCESS).toBe('SET_MODE_SUCCESS');
    });

    it('should have disconnect message', () => {
      expect(ProtocolMessages.DISCONNECT).toBe('SatoriEye_DISCONNECT');
    });
  });

  describe('PWM_CONSTANTS', () => {
    it('should have correct PWM range', () => {
      expect(PWM_CONSTANTS.MIN_VALUE).toBe(500);
      expect(PWM_CONSTANTS.MAX_VALUE).toBe(2500);
      expect(PWM_CONSTANTS.CENTER_VALUE).toBe(1500);
    });

    it('should have correct default values', () => {
      expect(PWM_CONSTANTS.DEFAULT_RANGE).toBe(250);
      expect(PWM_CONSTANTS.DEFAULT_INTERVAL).toBe(2550);
    });

    it('should have valid PWM range (2000 microseconds)', () => {
      const range = PWM_CONSTANTS.MAX_VALUE - PWM_CONSTANTS.MIN_VALUE;
      expect(range).toBe(2000);
    });

    it('should have center value at midpoint', () => {
      const midpoint = (PWM_CONSTANTS.MIN_VALUE + PWM_CONSTANTS.MAX_VALUE) / 2;
      expect(PWM_CONSTANTS.CENTER_VALUE).toBe(midpoint);
    });
  });

  describe('NETWORK_CONSTANTS', () => {
    it('should have correct port configuration', () => {
      expect(NETWORK_CONSTANTS.CLIENT_PORT).toBe(8889);
      expect(NETWORK_CONSTANTS.SERVER_PORT).toBe(8888);
    });

    it('should have correct addresses', () => {
      expect(NETWORK_CONSTANTS.BROADCAST_ADDRESS).toBe('224.0.0.1');
      expect(NETWORK_CONSTANTS.LOCALHOST).toBe('127.0.0.1');
    });

    it('should have correct timing values', () => {
      expect(NETWORK_CONSTANTS.HEARTBEAT_INTERVAL).toBe(20000);
      expect(NETWORK_CONSTANTS.RECONNECT_INTERVAL).toBe(10000);
      expect(NETWORK_CONSTANTS.MAX_RECONNECT_ATTEMPTS).toBe(5);
    });
  });

  describe('MODE_NAMES', () => {
    it('should map all EyeMode values to strings', () => {
      expect(MODE_NAMES[EyeMode.Unconnected]).toBe('未连接');
      expect(MODE_NAMES[EyeMode.Auto]).toBe('自动追踪');
      expect(MODE_NAMES[EyeMode.Manual]).toBe('手动操控');
      expect(MODE_NAMES[EyeMode.Sleep]).toBe('休眠');
      expect(MODE_NAMES[EyeMode.FacialRecognition]).toBe('人脸追踪');
    });

    it('should have entries for all modes', () => {
      const modeCount = Object.values(EyeMode).filter(v => typeof v === 'number').length;
      const nameCount = Object.keys(MODE_NAMES).length;
      expect(nameCount).toBe(modeCount);
    });
  });
});
