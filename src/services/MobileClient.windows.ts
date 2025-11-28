/**
 * Windows stub for MobileClient (UDP)
 * UDP networking through react-native-udp is not supported on Windows
 *
 * TODO: Implement using native Windows sockets or WebSocket fallback
 */
import {
  EyeMode,
  ChannelValues,
  ConnectionState,
  ConnectionType,
  PWM_CONSTANTS,
  ActionFrame,
} from '../types';

export type ConnectionCallback = (state: ConnectionState) => void;
export type ModeCallback = (mode: EyeMode) => void;
export type BatteryCallback = (battery: number) => void;

class MobileClient {
  private connectionState: ConnectionState = {
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
  };

  private currentMode: EyeMode = EyeMode.Unconnected;
  private battery: number = 0;

  private onConnectionChange: ConnectionCallback | null = null;
  private onModeChange: ModeCallback | null = null;
  private onBatteryChange: BatteryCallback | null = null;

  setCallbacks(
    onConnection: ConnectionCallback,
    onMode: ModeCallback,
    onBattery: BatteryCallback,
  ) {
    this.onConnectionChange = onConnection;
    this.onModeChange = onMode;
    this.onBatteryChange = onBattery;
  }

  findServer(): void {
    console.warn('UDP networking is not supported on Windows yet');
    // Could implement WebSocket fallback here in the future
  }

  disconnect(): void {
    this.connectionState = {
      ...this.connectionState,
      isConnected: false,
      connectionType: ConnectionType.None,
    };
    this.currentMode = EyeMode.Unconnected;
    this.onConnectionChange?.(this.connectionState);
    this.onModeChange?.(this.currentMode);
  }

  setMode(mode: EyeMode): void {
    console.warn('UDP setMode is not supported on Windows');
    this.currentMode = mode;
    this.onModeChange?.(mode);
  }

  updateChannelValues(
    _ch1: number,
    _ch2: number,
    _ch3: number,
    _smooth?: boolean,
    _duration?: number,
  ): void {
    // No-op on Windows
  }

  updateChannelValuesWithProportions(
    _ch1Prop: number,
    _ch2Prop: number,
    _ch3Prop: number,
  ): void {
    // No-op on Windows
  }

  async playFrames(_frames: ActionFrame[]): Promise<void> {
    // No-op on Windows
  }

  setAutoWinkEnabled(_enabled: boolean): void {
    // No-op on Windows
  }

  setAutoModeParameters(_range: number, _interval: number): void {
    // No-op on Windows
  }

  getConnectionState(): ConnectionState {
    return this.connectionState;
  }

  getCurrentMode(): EyeMode {
    return this.currentMode;
  }

  getBattery(): number {
    return this.battery;
  }

  sendRawMessage(_message: string): void {
    console.warn('UDP sendRawMessage is not supported on Windows');
  }

  destroy(): void {
    this.disconnect();
  }
}

export const mobileClient = new MobileClient();
export default MobileClient;
