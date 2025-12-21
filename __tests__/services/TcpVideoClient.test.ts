/**
 * TcpVideoClient Tests
 */

import { TcpVideoClient, TcpConnectionState } from '../../src/services/TcpVideoClient';

// Mock react-native-tcp-socket
const mockSocket = {
  on: jest.fn(),
  destroy: jest.fn(),
  write: jest.fn(),
};

jest.mock('react-native-tcp-socket', () => ({
  createConnection: jest.fn((options, callback) => {
    // Simulate successful connection
    setTimeout(() => {
      if (callback) callback();
    }, 10);

    return mockSocket;
  }),
}));

// Mock FramePacketParser
jest.mock('../../src/services/FramePacketParser', () => ({
  getFramePacketParser: jest.fn(() => ({
    parseHeader: jest.fn((buffer) => {
      if (buffer.length >= 12) {
        return {
          magic: 0xFFD8,
          frameId: 1,
          totalChunks: 1,
          chunkId: 0,
          chunkSize: buffer.length - 12,
        };
      }
      return null;
    }),
    parsePacket: jest.fn((buffer) => {
      if (buffer.length >= 12) {
        return {
          header: {
            magic: 0xFFD8,
            frameId: 1,
            totalChunks: 1,
            chunkId: 0,
            chunkSize: buffer.length - 12,
          },
          data: buffer.slice(12),
        };
      }
      return null;
    }),
    getExpectedPacketSize: jest.fn((header) => 12 + header.chunkSize),
    validatePacket: jest.fn(() => true),
  })),
}));

describe('TcpVideoClient', () => {
  let client: TcpVideoClient;

  beforeEach(() => {
    jest.clearAllMocks();
    mockSocket.on.mockClear();
    mockSocket.destroy.mockClear();
    client = new TcpVideoClient();
  });

  afterEach(() => {
    client.disconnect();
  });

  describe('connect', () => {
    it('should connect to specified host and port', (done) => {
      const TcpSocket = require('react-native-tcp-socket');

      client.connect('192.168.1.100', 8888);

      expect(TcpSocket.createConnection).toHaveBeenCalledWith(
        expect.objectContaining({
          host: '192.168.1.100',
          port: 8888,
        }),
        expect.any(Function)
      );

      setTimeout(() => {
        expect(client.getConnectionState()).toBe(TcpConnectionState.Connected);
        done();
      }, 50);
    });

    it('should set state to connecting initially', () => {
      client.connect('192.168.1.100', 8888);
      const state = client.getConnectionState();
      expect([TcpConnectionState.Connecting, TcpConnectionState.Connected]).toContain(state);
    });

    it('should not connect if already connected', (done) => {
      const TcpSocket = require('react-native-tcp-socket');

      client.connect('192.168.1.100', 8888);

      setTimeout(() => {
        const callCount = TcpSocket.createConnection.mock.calls.length;
        client.connect('192.168.1.100', 8888);

        expect(TcpSocket.createConnection.mock.calls.length).toBe(callCount);
        done();
      }, 50);
    });
  });

  describe('disconnect', () => {
    it('should disconnect and set state', (done) => {
      client.connect('192.168.1.100', 8888);

      setTimeout(() => {
        client.disconnect();
        expect(client.getConnectionState()).toBe(TcpConnectionState.Disconnected);
        done();
      }, 50);
    });
  });

  describe('isConnected', () => {
    it('should return false when disconnected', () => {
      expect(client.isConnected()).toBe(false);
    });

    it('should return true when connected', (done) => {
      client.connect('192.168.1.100', 8888);

      setTimeout(() => {
        expect(client.isConnected()).toBe(true);
        done();
      }, 50);
    });
  });

  describe('callbacks', () => {
    it('should allow registering packet callback', () => {
      const callback = jest.fn();
      const unsubscribe = client.onPacketReceived(callback);

      expect(typeof unsubscribe).toBe('function');
    });

    it('should allow registering error callback', () => {
      const callback = jest.fn();
      const unsubscribe = client.onError(callback);

      expect(typeof unsubscribe).toBe('function');
    });

    it('should allow registering state change callback', () => {
      const callback = jest.fn();
      const unsubscribe = client.onStateChange(callback);

      expect(typeof unsubscribe).toBe('function');
    });
  });

  describe('getConnectionState', () => {
    it('should return disconnected initially', () => {
      expect(client.getConnectionState()).toBe(TcpConnectionState.Disconnected);
    });

    it('should return connected after successful connection', (done) => {
      client.connect('192.168.1.100', 8888);

      setTimeout(() => {
        expect(client.getConnectionState()).toBe(TcpConnectionState.Connected);
        done();
      }, 50);
    });
  });
});
