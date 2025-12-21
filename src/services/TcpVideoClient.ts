/**
 * TCP Video Client
 *
 * Manages TCP connection to ESP32 device and receives video packets
 */

import TcpSocket from 'react-native-tcp-socket';
import type { Socket } from 'react-native-tcp-socket';
import { getPacketHeaderSize } from '../utils/BinaryProtocol';
import { getFramePacketParser, type ParsedPacket } from './FramePacketParser';
import { TCP_VIDEO_CONSTANTS } from '../types';

type PacketCallback = (packet: ParsedPacket) => void;
type ErrorCallback = (error: Error) => void;
type ConnectionStateCallback = (connected: boolean) => void;

export enum TcpConnectionState {
  Disconnected = 'disconnected',
  Connecting = 'connecting',
  Connected = 'connected',
  Error = 'error',
}

export class TcpVideoClient {
  private socket: Socket | null = null;
  private state: TcpConnectionState = TcpConnectionState.Disconnected;
  private parser = getFramePacketParser();
  private buffer: Uint8Array = new Uint8Array(0);
  private packetCallbacks: Set<PacketCallback> = new Set();
  private errorCallbacks: Set<ErrorCallback> = new Set();
  private stateCallbacks: Set<ConnectionStateCallback> = new Set();
  private host: string | null = null;
  private port: number | null = null;
  private reconnectTimeout: NodeJS.Timeout | null = null;
  private shouldReconnect = false;

  /**
   * Connect to TCP video server
   */
  connect(host: string, port: number, reconnectOnError = true): void {
    if (this.state === TcpConnectionState.Connected) {
      console.log('[TcpVideoClient] Already connected');
      return;
    }

    if (this.state === TcpConnectionState.Connecting) {
      console.log('[TcpVideoClient] Already connecting');
      return;
    }

    this.host = host;
    this.port = port;
    this.shouldReconnect = reconnectOnError;
    this.setState(TcpConnectionState.Connecting);

    console.log(`[TcpVideoClient] Connecting to ${host}:${port}`);

    try {
      this.socket = TcpSocket.createConnection(
        {
          host,
          port,
          timeout: TCP_VIDEO_CONSTANTS.CONNECTION_TIMEOUT,
        },
        () => {
          console.log('[TcpVideoClient] Connected');
          this.setState(TcpConnectionState.Connected);
          this.buffer = new Uint8Array(0);
        }
      );

      this.socket.on('data', (data: Uint8Array) => {
        this.handleData(data);
      });

      this.socket.on('error', (error: Error) => {
        console.error('[TcpVideoClient] Socket error:', error);
        this.setState(TcpConnectionState.Error);
        this.notifyError(error);
        this.handleDisconnect();
      });

      this.socket.on('close', () => {
        console.log('[TcpVideoClient] Connection closed');
        this.handleDisconnect();
      });
    } catch (error) {
      console.error('[TcpVideoClient] Failed to connect:', error);
      this.setState(TcpConnectionState.Error);
      this.notifyError(error as Error);
      this.handleDisconnect();
    }
  }

  /**
   * Disconnect from TCP server
   */
  disconnect(): void {
    this.shouldReconnect = false;

    if (this.reconnectTimeout) {
      clearTimeout(this.reconnectTimeout);
      this.reconnectTimeout = null;
    }

    if (this.socket) {
      this.socket.destroy();
      this.socket = null;
    }

    this.setState(TcpConnectionState.Disconnected);
    this.buffer = new Uint8Array(0);
    console.log('[TcpVideoClient] Disconnected');
  }

  /**
   * Get current connection state
   */
  getConnectionState(): TcpConnectionState {
    return this.state;
  }

  /**
   * Check if connected
   */
  isConnected(): boolean {
    return this.state === TcpConnectionState.Connected;
  }

  /**
   * Register callback for received packets
   */
  onPacketReceived(callback: PacketCallback): () => void {
    this.packetCallbacks.add(callback);
    return () => {
      this.packetCallbacks.delete(callback);
    };
  }

  /**
   * Register callback for errors
   */
  onError(callback: ErrorCallback): () => void {
    this.errorCallbacks.add(callback);
    return () => {
      this.errorCallbacks.delete(callback);
    };
  }

  /**
   * Register callback for connection state changes
   */
  onStateChange(callback: ConnectionStateCallback): () => void {
    this.stateCallbacks.add(callback);
    return () => {
      this.stateCallbacks.delete(callback);
    };
  }

  /**
   * Handle incoming data
   */
  private handleData(data: Uint8Array): void {
    // Append new data to buffer
    const newBuffer = new Uint8Array(this.buffer.length + data.length);
    newBuffer.set(this.buffer);
    newBuffer.set(data, this.buffer.length);
    this.buffer = newBuffer;

    // Try to parse packets from buffer
    this.parsePacketsFromBuffer();
  }

  /**
   * Parse packets from accumulated buffer
   */
  private parsePacketsFromBuffer(): void {
    const headerSize = getPacketHeaderSize();

    while (this.buffer.length >= headerSize) {
      // Parse header to get expected packet size
      const header = this.parser.parseHeader(this.buffer);
      if (!header) {
        // Invalid header, discard first byte and try again
        console.warn('[TcpVideoClient] Invalid header, discarding byte');
        this.buffer = this.buffer.slice(1);
        continue;
      }

      const expectedSize = this.parser.getExpectedPacketSize(header);

      // Check if we have complete packet
      if (this.buffer.length < expectedSize) {
        // Wait for more data
        break;
      }

      // Extract packet
      const packetBuffer = this.buffer.slice(0, expectedSize);
      this.buffer = this.buffer.slice(expectedSize);

      // Parse complete packet
      const packet = this.parser.parsePacket(packetBuffer);
      if (packet && this.parser.validatePacket(packet)) {
        this.notifyPacket(packet);
      } else {
        console.warn('[TcpVideoClient] Invalid packet');
      }
    }
  }

  /**
   * Handle disconnection
   */
  private handleDisconnect(): void {
    if (this.socket) {
      this.socket.destroy();
      this.socket = null;
    }

    this.setState(TcpConnectionState.Disconnected);
    this.buffer = new Uint8Array(0);

    // Attempt reconnection if enabled
    if (this.shouldReconnect && this.host && this.port) {
      console.log('[TcpVideoClient] Reconnecting in 3 seconds...');
      this.reconnectTimeout = setTimeout(() => {
        if (this.host && this.port) {
          this.connect(this.host, this.port, this.shouldReconnect);
        }
      }, 3000);
    }
  }

  /**
   * Set connection state and notify callbacks
   */
  private setState(state: TcpConnectionState): void {
    if (this.state !== state) {
      this.state = state;
      const isConnected = state === TcpConnectionState.Connected;
      this.stateCallbacks.forEach(callback => {
        try {
          callback(isConnected);
        } catch (error) {
          console.error('[TcpVideoClient] Error in state callback:', error);
        }
      });
    }
  }

  /**
   * Notify packet callbacks
   */
  private notifyPacket(packet: ParsedPacket): void {
    this.packetCallbacks.forEach(callback => {
      try {
        callback(packet);
      } catch (error) {
        console.error('[TcpVideoClient] Error in packet callback:', error);
      }
    });
  }

  /**
   * Notify error callbacks
   */
  private notifyError(error: Error): void {
    this.errorCallbacks.forEach(callback => {
      try {
        callback(error);
      } catch (err) {
        console.error('[TcpVideoClient] Error in error callback:', err);
      }
    });
  }
}

// Singleton instance
let tcpClientInstance: TcpVideoClient | null = null;

/**
 * Get the singleton instance of TcpVideoClient
 */
export function getTcpVideoClient(): TcpVideoClient {
  if (!tcpClientInstance) {
    tcpClientInstance = new TcpVideoClient();
  }
  return tcpClientInstance;
}
