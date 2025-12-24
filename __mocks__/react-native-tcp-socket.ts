/**
 * Manual mock for react-native-tcp-socket
 */

export const TcpServer = jest.fn();
export const TcpSocket = jest.fn();

export const createServer = jest.fn(() => ({
  listen: jest.fn(),
  address: jest.fn().mockReturnValue({ address: '127.0.0.1', port: 8080, family: 'IPv4' }),
  on: jest.fn(),
  close: jest.fn(),
  destroy: jest.fn(),
}));

export const createConnection = jest.fn(() => ({
  on: jest.fn(),
  write: jest.fn(),
  end: jest.fn(),
  destroy: jest.fn(),
}));

export const Socket = jest.fn();

export default {
  createServer,
  createConnection,
  Socket,
  TcpServer,
  TcpSocket,
};
