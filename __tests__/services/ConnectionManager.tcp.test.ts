/**
 * ConnectionManager TCP Video Tests
 */

import { connectionManager } from '../../src/services/ConnectionManager';
import { ESP32Device } from '../../src/types';

// Mock services
jest.mock('../../src/services/UdpDiscoveryService', () => ({
  getUdpDiscoveryService: jest.fn(() => ({
    startDiscovery: jest.fn(),
    stopDiscovery: jest.fn(),
    getDiscoveredDevices: jest.fn(() => []),
    onDeviceUpdate: jest.fn(() => jest.fn()),
    onError: jest.fn(() => jest.fn()),
    isDiscovering: jest.fn(() => false),
  })),
}));

jest.mock('../../src/services/TcpVideoClient', () => ({
  getTcpVideoClient: jest.fn(() => ({
    connect: jest.fn(),
    disconnect: jest.fn(),
    isConnected: jest.fn(() => false),
    getConnectionState: jest.fn(() => 'disconnected'),
    onPacketReceived: jest.fn(() => jest.fn()),
    onError: jest.fn(() => jest.fn()),
    onStateChange: jest.fn(() => jest.fn()),
  })),
}));

jest.mock('../../src/services/TcpFrameAssembler', () => ({
  getTcpFrameAssembler: jest.fn(() => ({
    onPacket: jest.fn(),
    setFrameCallback: jest.fn(),
    getStats: jest.fn(() => ({
      droppedFrames: 0,
      receivedFrames: 0,
      avgLatency: 0,
      currentFPS: 0,
    })),
    resetStats: jest.fn(),
    destroy: jest.fn(),
  })),
}));

describe('ConnectionManager - TCP Video', () => {
  let mockDiscoveryService: any;
  let mockTcpClient: any;
  let mockFrameAssembler: any;

  beforeEach(() => {
    jest.clearAllMocks();

    const { getUdpDiscoveryService } = require('../../src/services/UdpDiscoveryService');
    const { getTcpVideoClient } = require('../../src/services/TcpVideoClient');
    const { getTcpFrameAssembler } = require('../../src/services/TcpFrameAssembler');

    mockDiscoveryService = getUdpDiscoveryService();
    mockTcpClient = getTcpVideoClient();
    mockFrameAssembler = getTcpFrameAssembler();
  });

  describe('device discovery', () => {
    it('should start device discovery', () => {
      connectionManager.startDeviceDiscovery();

      expect(mockDiscoveryService.startDiscovery).toHaveBeenCalled();
    });

    it('should stop device discovery', () => {
      connectionManager.stopDeviceDiscovery();

      expect(mockDiscoveryService.stopDiscovery).toHaveBeenCalled();
    });

    it('should get discovered devices', () => {
      const mockDevices: ESP32Device[] = [
        {
          deviceId: 'ESP32S3-CAM-001',
          ip: '192.168.1.100',
          tcpPort: 8888,
          heartbeatPort: 8889,
          fps: 15.0,
          lastSeen: Date.now(),
        },
      ];

      mockDiscoveryService.getDiscoveredDevices.mockReturnValue(mockDevices);

      const devices = connectionManager.getDiscoveredDevices();

      expect(devices).toEqual(mockDevices);
      expect(mockDiscoveryService.getDiscoveredDevices).toHaveBeenCalled();
    });

    it('should call device discovery callback when devices are discovered', () => {
      const callback = jest.fn();
      connectionManager.setCallbacks(
        jest.fn(),
        jest.fn(),
        jest.fn(),
        undefined,
        undefined,
        undefined,
        callback
      );

      // Get the callback registered with discovery service
      const registeredCallback = mockDiscoveryService.onDeviceUpdate.mock.calls[0][0];

      const mockDevices: ESP32Device[] = [
        {
          deviceId: 'ESP32S3-CAM-001',
          ip: '192.168.1.100',
          tcpPort: 8888,
          heartbeatPort: 8889,
          fps: 15.0,
          lastSeen: Date.now(),
        },
      ];

      // Simulate device discovery
      registeredCallback(mockDevices);

      expect(callback).toHaveBeenCalledWith(mockDevices);
    });
  });

  describe('video streaming', () => {
    const mockDevice: ESP32Device = {
      deviceId: 'ESP32S3-CAM-001',
      ip: '192.168.1.100',
      tcpPort: 8888,
      heartbeatPort: 8889,
      fps: 15.0,
      lastSeen: Date.now(),
    };

    it('should start video stream with device', () => {
      connectionManager.startVideoStream(mockDevice);

      expect(mockTcpClient.connect).toHaveBeenCalledWith('192.168.1.100', 8888, true);
      expect(mockFrameAssembler.resetStats).toHaveBeenCalled();
    });

    it('should stop video stream', () => {
      connectionManager.stopVideoStream();

      expect(mockTcpClient.disconnect).toHaveBeenCalled();
    });

    it('should get video stream statistics', () => {
      const mockStats = {
        droppedFrames: 5,
        receivedFrames: 100,
        avgLatency: 50,
        currentFPS: 15.5,
      };

      mockFrameAssembler.getStats.mockReturnValue(mockStats);

      const stats = connectionManager.getVideoStreamStats();

      expect(stats).toEqual(mockStats);
      expect(mockFrameAssembler.getStats).toHaveBeenCalled();
    });
  });

  describe('video frame pipeline', () => {
    it('should forward packets from TCP client to frame assembler', () => {
      // Get the packet callback registered with TCP client
      const packetCallback = mockTcpClient.onPacketReceived.mock.calls[0][0];

      const mockPacket = {
        header: {
          magic: 0xFFD8,
          frameId: 1,
          totalChunks: 1,
          chunkId: 0,
          chunkSize: 100,
        },
        data: new Uint8Array(100),
      };

      // Simulate packet reception
      packetCallback(mockPacket);

      expect(mockFrameAssembler.onPacket).toHaveBeenCalledWith(mockPacket);
    });

    it('should forward assembled frames to video frame callback', () => {
      const frameCallback = jest.fn();
      connectionManager.setCallbacks(
        jest.fn(),
        jest.fn(),
        jest.fn(),
        undefined,
        undefined,
        frameCallback
      );

      // Get the frame callback registered with frame assembler
      const assemblerCallback = mockFrameAssembler.setFrameCallback.mock.calls[0][0];

      const mockFrame = {
        frameId: 1,
        data: new Uint8Array(1000),
        timestamp: Date.now(),
        width: 640,
        height: 480,
      };

      // Simulate frame assembly
      assemblerCallback(mockFrame);

      expect(frameCallback).toHaveBeenCalledWith(mockFrame);
    });
  });

  describe('integration', () => {
    it('should set up complete video pipeline on initialization', () => {
      // Verify all services are connected
      expect(mockDiscoveryService.onDeviceUpdate).toHaveBeenCalled();
      expect(mockTcpClient.onPacketReceived).toHaveBeenCalled();
      expect(mockFrameAssembler.setFrameCallback).toHaveBeenCalled();
    });

    it('should handle end-to-end video streaming flow', () => {
      const frameCallback = jest.fn();
      connectionManager.setCallbacks(
        jest.fn(),
        jest.fn(),
        jest.fn(),
        undefined,
        undefined,
        frameCallback
      );

      const mockDevice: ESP32Device = {
        deviceId: 'ESP32S3-CAM-001',
        ip: '192.168.1.100',
        tcpPort: 8888,
        heartbeatPort: 8889,
        fps: 15.0,
        lastSeen: Date.now(),
      };

      // Start video stream
      connectionManager.startVideoStream(mockDevice);

      // Simulate packet reception
      const packetCallback = mockTcpClient.onPacketReceived.mock.calls[0][0];
      const mockPacket = {
        header: {
          magic: 0xFFD8,
          frameId: 1,
          totalChunks: 1,
          chunkId: 0,
          chunkSize: 100,
        },
        data: new Uint8Array(100),
      };
      packetCallback(mockPacket);

      // Simulate frame assembly
      const assemblerCallback = mockFrameAssembler.setFrameCallback.mock.calls[0][0];
      const mockFrame = {
        frameId: 1,
        data: new Uint8Array(1000),
        timestamp: Date.now(),
        width: 640,
        height: 480,
      };
      assemblerCallback(mockFrame);

      // Verify frame was delivered
      expect(frameCallback).toHaveBeenCalledWith(mockFrame);

      // Stop video stream
      connectionManager.stopVideoStream();
      expect(mockTcpClient.disconnect).toHaveBeenCalled();
    });
  });
});
