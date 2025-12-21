/**
 * UdpDiscoveryService Tests
 */

import { UdpDiscoveryService } from '../../src/services/UdpDiscoveryService';
import { ESP32Device } from '../../src/types';

// Mock react-native-udp
jest.mock('react-native-udp', () => ({
  createSocket: jest.fn(() => ({
    bind: jest.fn(),
    on: jest.fn(),
    close: jest.fn(),
    address: jest.fn(() => ({ address: '0.0.0.0', port: 8889 })),
  })),
}));

describe('UdpDiscoveryService', () => {
  let service: UdpDiscoveryService;
  let mockSocket: any;

  beforeEach(() => {
    jest.clearAllMocks();
    service = new UdpDiscoveryService();

    const dgram = require('react-native-udp');
    mockSocket = dgram.createSocket();
  });

  afterEach(() => {
    if (service.isDiscovering()) {
      service.stopDiscovery();
    }
  });

  describe('startDiscovery', () => {
    it('should start discovery and bind to port 8889', () => {
      service.startDiscovery();

      expect(mockSocket.bind).toHaveBeenCalledWith(8889);
      expect(service.isDiscovering()).toBe(true);
    });

    it('should not start if already running', () => {
      service.startDiscovery();
      const firstCallCount = mockSocket.bind.mock.calls.length;

      service.startDiscovery();
      expect(mockSocket.bind.mock.calls.length).toBe(firstCallCount);
    });

    it('should register message handler', () => {
      service.startDiscovery();
      expect(mockSocket.on).toHaveBeenCalledWith('message', expect.any(Function));
    });

    it('should register error handler', () => {
      service.startDiscovery();
      expect(mockSocket.on).toHaveBeenCalledWith('error', expect.any(Function));
    });

    it('should register listening handler', () => {
      service.startDiscovery();
      expect(mockSocket.on).toHaveBeenCalledWith('listening', expect.any(Function));
    });
  });

  describe('stopDiscovery', () => {
    it('should stop discovery and close socket', () => {
      service.startDiscovery();
      service.stopDiscovery();

      expect(mockSocket.close).toHaveBeenCalled();
      expect(service.isDiscovering()).toBe(false);
    });

    it('should clear discovered devices', () => {
      service.startDiscovery();
      service.stopDiscovery();

      expect(service.getDiscoveredDevices()).toEqual([]);
    });

    it('should do nothing if not running', () => {
      service.stopDiscovery();
      expect(mockSocket.close).not.toHaveBeenCalled();
    });
  });

  describe('device discovery', () => {
    it('should parse valid heartbeat message', () => {
      const heartbeat = {
        type: 'heartbeat',
        device_id: 'ESP32S3-CAM-001',
        ip: '192.168.1.100',
        tcp_port: 8888,
        heartbeat_port: 8889,
        fps: 15.5,
      };

      service.startDiscovery();

      // Get the message handler
      const messageHandler = mockSocket.on.mock.calls.find(
        (call: any) => call[0] === 'message'
      )?.[1];

      // Simulate receiving a heartbeat
      const buffer = Buffer.from(JSON.stringify(heartbeat));
      messageHandler(buffer, { address: '192.168.1.100', port: 8889 });

      const devices = service.getDiscoveredDevices();
      expect(devices).toHaveLength(1);
      expect(devices[0].deviceId).toBe('ESP32S3-CAM-001');
      expect(devices[0].ip).toBe('192.168.1.100');
      expect(devices[0].tcpPort).toBe(8888);
      expect(devices[0].fps).toBe(15.5);
    });

    it('should ignore invalid heartbeat messages', () => {
      service.startDiscovery();

      const messageHandler = mockSocket.on.mock.calls.find(
        (call: any) => call[0] === 'message'
      )?.[1];

      // Invalid: missing required fields
      const invalidHeartbeat = {
        type: 'heartbeat',
        device_id: 'ESP32S3-CAM-001',
        // Missing ip and tcp_port
      };

      const buffer = Buffer.from(JSON.stringify(invalidHeartbeat));
      messageHandler(buffer, { address: '192.168.1.100', port: 8889 });

      expect(service.getDiscoveredDevices()).toHaveLength(0);
    });

    it('should ignore non-heartbeat messages', () => {
      service.startDiscovery();

      const messageHandler = mockSocket.on.mock.calls.find(
        (call: any) => call[0] === 'message'
      )?.[1];

      const otherMessage = {
        type: 'other',
        data: 'something',
      };

      const buffer = Buffer.from(JSON.stringify(otherMessage));
      messageHandler(buffer, { address: '192.168.1.100', port: 8889 });

      expect(service.getDiscoveredDevices()).toHaveLength(0);
    });

    it('should update existing device on new heartbeat', () => {
      service.startDiscovery();

      const messageHandler = mockSocket.on.mock.calls.find(
        (call: any) => call[0] === 'message'
      )?.[1];

      // First heartbeat
      const heartbeat1 = {
        type: 'heartbeat',
        device_id: 'ESP32S3-CAM-001',
        ip: '192.168.1.100',
        tcp_port: 8888,
        heartbeat_port: 8889,
        fps: 15.0,
      };

      messageHandler(Buffer.from(JSON.stringify(heartbeat1)), {});

      // Second heartbeat with updated FPS
      const heartbeat2 = {
        ...heartbeat1,
        fps: 20.0,
      };

      messageHandler(Buffer.from(JSON.stringify(heartbeat2)), {});

      const devices = service.getDiscoveredDevices();
      expect(devices).toHaveLength(1);
      expect(devices[0].fps).toBe(20.0);
    });

    it('should handle multiple devices', () => {
      service.startDiscovery();

      const messageHandler = mockSocket.on.mock.calls.find(
        (call: any) => call[0] === 'message'
      )?.[1];

      const device1 = {
        type: 'heartbeat',
        device_id: 'ESP32S3-CAM-001',
        ip: '192.168.1.100',
        tcp_port: 8888,
        heartbeat_port: 8889,
        fps: 15.0,
      };

      const device2 = {
        type: 'heartbeat',
        device_id: 'ESP32S3-CAM-002',
        ip: '192.168.1.101',
        tcp_port: 8888,
        heartbeat_port: 8889,
        fps: 20.0,
      };

      messageHandler(Buffer.from(JSON.stringify(device1)), {});
      messageHandler(Buffer.from(JSON.stringify(device2)), {});

      const devices = service.getDiscoveredDevices();
      expect(devices).toHaveLength(2);
    });
  });

  describe('callbacks', () => {
    it('should call device update callback when device discovered', () => {
      const callback = jest.fn();
      service.onDeviceUpdate(callback);
      service.startDiscovery();

      const messageHandler = mockSocket.on.mock.calls.find(
        (call: any) => call[0] === 'message'
      )?.[1];

      const heartbeat = {
        type: 'heartbeat',
        device_id: 'ESP32S3-CAM-001',
        ip: '192.168.1.100',
        tcp_port: 8888,
        heartbeat_port: 8889,
        fps: 15.0,
      };

      messageHandler(Buffer.from(JSON.stringify(heartbeat)), {});

      expect(callback).toHaveBeenCalled();
      expect(callback.mock.calls[0][0]).toHaveLength(1);
    });

    it('should unregister callback when unsubscribe is called', () => {
      const callback = jest.fn();
      const unsubscribe = service.onDeviceUpdate(callback);

      unsubscribe();
      service.startDiscovery();

      const messageHandler = mockSocket.on.mock.calls.find(
        (call: any) => call[0] === 'message'
      )?.[1];

      const heartbeat = {
        type: 'heartbeat',
        device_id: 'ESP32S3-CAM-001',
        ip: '192.168.1.100',
        tcp_port: 8888,
        heartbeat_port: 8889,
        fps: 15.0,
      };

      messageHandler(Buffer.from(JSON.stringify(heartbeat)), {});

      expect(callback).not.toHaveBeenCalled();
    });

    it('should call error callback on socket error', () => {
      const errorCallback = jest.fn();
      service.onError(errorCallback);
      service.startDiscovery();

      const errorHandler = mockSocket.on.mock.calls.find(
        (call: any) => call[0] === 'error'
      )?.[1];

      const error = new Error('Socket error');
      errorHandler(error);

      expect(errorCallback).toHaveBeenCalledWith(error);
    });
  });

  describe('stale device removal', () => {
    it('should remove stale devices after timeout', (done) => {
      jest.useFakeTimers();

      service.startDiscovery();

      const messageHandler = mockSocket.on.mock.calls.find(
        (call: any) => call[0] === 'message'
      )?.[1];

      const heartbeat = {
        type: 'heartbeat',
        device_id: 'ESP32S3-CAM-001',
        ip: '192.168.1.100',
        tcp_port: 8888,
        heartbeat_port: 8889,
        fps: 15.0,
      };

      messageHandler(Buffer.from(JSON.stringify(heartbeat)), {});
      expect(service.getDiscoveredDevices()).toHaveLength(1);

      // Fast-forward time past stale timeout (10 seconds)
      jest.advanceTimersByTime(11000);

      expect(service.getDiscoveredDevices()).toHaveLength(0);

      jest.useRealTimers();
      done();
    });
  });
});
