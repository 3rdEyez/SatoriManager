/**
 * Windows stub for BluetoothClient
 * BLE is not supported on Windows through react-native-ble-plx
 */
import {
  EyeMode,
  BluetoothDevice,
  BluetoothScanState,
  ActionFrame,
} from '../types';

export type BluetoothConnectionCallback = (isConnected: boolean, device?: BluetoothDevice) => void;
export type BluetoothScanCallback = (state: BluetoothScanState) => void;
export type ModeCallback = (mode: EyeMode) => void;
export type BatteryCallback = (battery: number) => void;

class BluetoothClient {
  private scanState: BluetoothScanState = {
    isScanning: false,
    devices: [],
    error: 'Bluetooth is not supported on Windows',
  };

  private onConnectionChange: BluetoothConnectionCallback | null = null;
  private onScanStateChange: BluetoothScanCallback | null = null;
  private onModeChange: ModeCallback | null = null;
  private onBatteryChange: BatteryCallback | null = null;

  setCallbacks(
    onConnection: BluetoothConnectionCallback,
    onScan: BluetoothScanCallback,
    onMode: ModeCallback,
    onBattery: BatteryCallback,
  ) {
    this.onConnectionChange = onConnection;
    this.onScanStateChange = onScan;
    this.onModeChange = onMode;
    this.onBatteryChange = onBattery;
  }

  async startScan(): Promise<void> {
    console.warn('Bluetooth scanning is not supported on Windows');
    this.scanState = {
      isScanning: false,
      devices: [],
      error: 'Bluetooth is not supported on Windows',
    };
    this.onScanStateChange?.(this.scanState);
  }

  stopScan(): void {
    // No-op on Windows
  }

  async connect(_deviceId: string): Promise<boolean> {
    console.warn('Bluetooth connection is not supported on Windows');
    return false;
  }

  disconnect(): void {
    // No-op on Windows
  }

  setMode(_mode: EyeMode): void {
    console.warn('Bluetooth setMode is not supported on Windows');
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

  getScanState(): BluetoothScanState {
    return this.scanState;
  }

  sendRawMessage(_message: string): void {
    // No-op on Windows
  }

  destroy(): void {
    // No-op on Windows
  }
}

export const bluetoothClient = new BluetoothClient();
export default BluetoothClient;
