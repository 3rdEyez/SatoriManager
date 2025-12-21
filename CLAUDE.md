# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Setup & Run
- **Install dependencies**: `pnpm install`
- **Start Metro server**: `pnpm start`
- **Run Android**: `pnpm android`
- **Run iOS**: `pnpm ios` (macOS only)
- **Run Windows**: `pnpm windows` (Windows only)
- **Pod install (iOS)**: `cd ios && pod install`

### Testing & Linting
- **Run tests**: `pnpm test`
- **Run single test**: `pnpm test -- path/to/file.test.ts`
- **Watch mode**: `pnpm test:watch`
- **Coverage**: `pnpm test:coverage`
- **Lint**: `pnpm lint`
- **Typecheck**: `pnpm typecheck`

## Architecture

### Overview
This is a React Native mobile application for controlling the "SatoriEye" robot. It supports both Android and iOS, with experimental Windows support.

### State Management
- **Zustand** is used for global state management (`src/store/appStore.ts`).

### Communication Architecture
The app connects to the robot hardware via multiple methods:
1. **WiFi (UDP)**: Managed by `src/services/MobileClient.ts`. Used for local network discovery and low-latency control.
2. **Bluetooth (BLE)**: Managed by `src/services/BluetoothClient.ts` using `react-native-ble-plx`. Used for direct connection.
3. **TCP Video Streaming**: Managed by `src/services/TcpVideoClient.ts`. Used for real-time video streaming from ESP32-S3 cameras.
4. **ConnectionManager**: `src/services/ConnectionManager.ts` abstracts these methods, providing a unified interface for the UI.

### Communication Protocols

#### Control Protocols
- **UDP Control**: Text-based protocol (e.g., `SET_MODE:<mode>`, `CH1:<val>CH2:<val>`).
- **BLE Control**: Custom binary protocol using Nordic UART Service (UUID: `6e400001-...`).
  - **Uplink (App -> Robot)**: 6-byte packets `[Header][CMD][Data1][Data2][Data3][Checksum]`.
  - **Downlink (Robot -> App)**: 8-byte telemetry packets.

#### TCP Video Streaming Protocol
The app uses a TCP-based binary protocol for receiving video streams from ESP32-S3 cameras:

**Device Discovery (UDP Port 8889)**:
- JSON heartbeat messages broadcast every 1-2 seconds
- Format: `{"type":"heartbeat","device_id":"ESP32S3-CAM","ip":"192.168.1.100","tcp_port":8888,"fps":15.0}`
- Devices are considered stale after 10 seconds without heartbeat

**Video Stream (TCP Port 8888)**:
- Binary packet format with 12-byte little-endian header + data
- Header structure: `[Magic 2B][Frame ID 4B][Total Chunks 2B][Chunk ID 2B][Chunk Size 2B]`
- Magic number: `0xFFD8` (JPEG magic)
- Frames are assembled from multiple chunks
- Supports out-of-order chunk reception

**Key Components**:
- `UdpDiscoveryService.ts`: Discovers ESP32 devices via UDP heartbeats
- `TcpVideoClient.ts`: Manages TCP connection and packet reception
- `FramePacketParser.ts`: Parses binary packet headers
- `TcpFrameAssembler.ts`: Assembles complete JPEG frames from chunks
- `BinaryProtocol.ts`: Utilities for little-endian binary parsing

### Project Structure
- `src/screens`: Main UI screens (MainScreen, ControlScreen, SettingScreen).
- `src/components`: Reusable UI components (Joystick, Dial, ConnectionModal).
- `src/services`: Communication logic and hardware abstraction.
- `src/store`: State management.
- `src/types`: TypeScript definitions.
- `android/` & `ios/`: Native platform code.
