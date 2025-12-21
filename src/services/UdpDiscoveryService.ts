/**
 * UDP Discovery Service
 *
 * Listens for UDP heartbeat messages from ESP32 devices
 * and maintains a list of discovered devices
 */

import dgram from 'react-native-udp';
import type { Socket } from 'react-native-udp';
import { ESP32Device, TCP_VIDEO_CONSTANTS } from '../types';

type DeviceUpdateCallback = (devices: ESP32Device[]) => void;
type ErrorCallback = (error: Error) => void;

interface HeartbeatMessage {
  type: string;
  device_id: string;
  ip: string;
  tcp_port: number;
  heartbeat_port: number;
  fps: number;
  rssi?: number;
}

export class UdpDiscoveryService {
  private socket: Socket | null = null;
  private devices: Map<string, ESP32Device> = new Map();
  private staleCheckInterval: NodeJS.Timeout | null = null;
  private deviceUpdateCallbacks: Set<DeviceUpdateCallback> = new Set();
  private errorCallbacks: Set<ErrorCallback> = new Set();
  private isRunning = false;

  /**
   * Start listening for device heartbeats
   */
  startDiscovery(): void {
    if (this.isRunning) {
      console.log('[UdpDiscoveryService] Already running');
      return;
    }

    try {
      this.socket = dgram.createSocket({
        type: 'udp4',
        reuseAddr: true,
      });

      this.socket.bind(TCP_VIDEO_CONSTANTS.DISCOVERY_PORT);

      this.socket.on('message', (msg: Buffer, rinfo: any) => {
        this.handleMessage(msg, rinfo);
      });

      this.socket.on('error', (err: Error) => {
        console.error('[UdpDiscoveryService] Socket error:', err);
        this.notifyError(err);
      });

      this.socket.on('listening', () => {
        const address = this.socket?.address();
        console.log(
          `[UdpDiscoveryService] Listening on ${address?.address}:${address?.port}`
        );
      });

      // Start stale device check interval
      this.staleCheckInterval = setInterval(() => {
        this.removeStaleDevices();
      }, 1000);

      this.isRunning = true;
      console.log('[UdpDiscoveryService] Discovery started');
    } catch (error) {
      console.error('[UdpDiscoveryService] Failed to start discovery:', error);
      this.notifyError(error as Error);
    }
  }

  /**
   * Stop listening for device heartbeats
   */
  stopDiscovery(): void {
    if (!this.isRunning) {
      return;
    }

    if (this.staleCheckInterval) {
      clearInterval(this.staleCheckInterval);
      this.staleCheckInterval = null;
    }

    if (this.socket) {
      this.socket.close();
      this.socket = null;
    }

    this.devices.clear();
    this.isRunning = false;
    console.log('[UdpDiscoveryService] Discovery stopped');
  }

  /**
   * Get the list of currently discovered devices
   */
  getDiscoveredDevices(): ESP32Device[] {
    return Array.from(this.devices.values());
  }

  /**
   * Register a callback for device list updates
   */
  onDeviceUpdate(callback: DeviceUpdateCallback): () => void {
    this.deviceUpdateCallbacks.add(callback);
    return () => {
      this.deviceUpdateCallbacks.delete(callback);
    };
  }

  /**
   * Register a callback for errors
   */
  onError(callback: ErrorCallback): () => void {
    this.errorCallbacks.add(callback);
    return () => {
      this.errorCallbacks.delete(callback);
    };
  }

  /**
   * Check if discovery is running
   */
  isDiscovering(): boolean {
    return this.isRunning;
  }

  /**
   * Handle incoming UDP message
   */
  private handleMessage(msg: Buffer, rinfo: any): void {
    try {
      const message = msg.toString('utf8');
      const heartbeat = JSON.parse(message) as HeartbeatMessage;

      // Validate heartbeat message
      if (
        heartbeat.type !== 'heartbeat' ||
        !heartbeat.device_id ||
        !heartbeat.ip ||
        !heartbeat.tcp_port
      ) {
        console.warn('[UdpDiscoveryService] Invalid heartbeat message:', message);
        return;
      }

      // Create or update device
      const device: ESP32Device = {
        deviceId: heartbeat.device_id,
        ip: heartbeat.ip,
        tcpPort: heartbeat.tcp_port,
        heartbeatPort: heartbeat.heartbeat_port || TCP_VIDEO_CONSTANTS.DISCOVERY_PORT,
        fps: heartbeat.fps || 0,
        lastSeen: Date.now(),
        rssi: heartbeat.rssi,
      };

      const isNewDevice = !this.devices.has(device.deviceId);
      this.devices.set(device.deviceId, device);

      if (isNewDevice) {
        console.log('[UdpDiscoveryService] New device discovered:', device.deviceId);
      }

      // Notify callbacks
      this.notifyDeviceUpdate();
    } catch (error) {
      console.error('[UdpDiscoveryService] Failed to parse heartbeat:', error);
    }
  }

  /**
   * Remove devices that haven't sent a heartbeat recently
   */
  private removeStaleDevices(): void {
    const now = Date.now();
    let removedCount = 0;

    for (const [deviceId, device] of this.devices.entries()) {
      if (now - device.lastSeen > TCP_VIDEO_CONSTANTS.DEVICE_STALE_TIMEOUT) {
        this.devices.delete(deviceId);
        removedCount++;
        console.log('[UdpDiscoveryService] Removed stale device:', deviceId);
      }
    }

    if (removedCount > 0) {
      this.notifyDeviceUpdate();
    }
  }

  /**
   * Notify all device update callbacks
   */
  private notifyDeviceUpdate(): void {
    const devices = this.getDiscoveredDevices();
    this.deviceUpdateCallbacks.forEach(callback => {
      try {
        callback(devices);
      } catch (error) {
        console.error('[UdpDiscoveryService] Error in device update callback:', error);
      }
    });
  }

  /**
   * Notify all error callbacks
   */
  private notifyError(error: Error): void {
    this.errorCallbacks.forEach(callback => {
      try {
        callback(error);
      } catch (err) {
        console.error('[UdpDiscoveryService] Error in error callback:', err);
      }
    });
  }
}

// Singleton instance
let discoveryServiceInstance: UdpDiscoveryService | null = null;

/**
 * Get the singleton instance of UdpDiscoveryService
 */
export function getUdpDiscoveryService(): UdpDiscoveryService {
  if (!discoveryServiceInstance) {
    discoveryServiceInstance = new UdpDiscoveryService();
  }
  return discoveryServiceInstance;
}
