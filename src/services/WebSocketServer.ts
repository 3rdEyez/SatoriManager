/**
 * WebSocket Server
 * HTTP/WebSocket 服务器 - 用于向外部浏览器推送读心结果
 */

import TcpSocket from 'react-native-tcp-socket';
import type { Socket } from 'react-native-tcp-socket';
import { MindReadingResult } from '../types';
import { WEBSOCKET_SERVER_CONFIG } from '../constants/MindReadingDefaults';

type StateChangeCallback = (running: boolean, url: string | null) => void;

/**
 * WebSocket Server Class
 */
export class WebSocketServer {
  private server: any = null;
  private wsClients: Set<Socket> = new Set();
  private port: number = 8080;
  private isRunning: boolean = false;
  private serverUrl: string | null = null;
  private stateCallbacks: Set<StateChangeCallback> = new Set();

  constructor() {
    // 获取本机 IP 地址
    this.getLocalIpAddress();
  }

  /**
   * 启动服务器
   */
  async start(port: number): Promise<string> {
    if (this.isRunning) {
      console.log('[WebSocketServer] Server already running');
      return this.serverUrl || '';
    }

    this.port = port;

    return new Promise((resolve, reject) => {
      try {
        this.server = TcpSocket.createServer((socket: Socket) => {
          this.handleConnection(socket);
        });

        this.server.listen({ port, host: '0.0.0.0' }, () => {
          console.log(`[WebSocketServer] Server listening on port ${port}`);
          this.isRunning = true;
          this.notifyStateChange(true, this.serverUrl);
          resolve(this.serverUrl || '');
        });

        this.server.on('error', (error: Error) => {
          console.error('[WebSocketServer] Server error:', error);
          this.isRunning = false;
          this.notifyStateChange(false, null);
          reject(error);
        });
      } catch (error) {
        console.error('[WebSocketServer] Failed to start server:', error);
        reject(error);
      }
    });
  }

  /**
   * 停止服务器
   */
  stop(): void {
    if (!this.isRunning) {
      return;
    }

    console.log('[WebSocketServer] Stopping server...');

    // 关闭所有 WebSocket 连接
    this.wsClients.forEach(client => {
      try {
        client.destroy();
      } catch (error) {
        console.error('[WebSocketServer] Error closing client:', error);
      }
    });
    this.wsClients.clear();

    // 关闭服务器
    if (this.server) {
      try {
        this.server.close();
      } catch (error) {
        console.error('[WebSocketServer] Error closing server:', error);
      }
      this.server = null;
    }

    this.isRunning = false;
    this.notifyStateChange(false, null);
  }

  /**
   * 获取服务器状态
   */
  getIsRunning(): boolean {
    return this.isRunning;
  }

  /**
   * 获取服务器 URL
   */
  getServerUrl(): string | null {
    return this.serverUrl;
  }

  /**
   * 广播结果到所有 WebSocket 客户端
   */
  broadcast(result: MindReadingResult): void {
    if (this.wsClients.size === 0) {
      return;
    }

    console.log(`[WebSocketServer] Broadcasting to ${this.wsClients.size} clients`);

    const payload = JSON.stringify(result);
    const frame = this.createWebSocketFrame(payload);
    const failedClients: Socket[] = [];

    this.wsClients.forEach(client => {
      try {
        if (client.writable) {
          client.write(frame);
        } else {
          failedClients.push(client);
        }
      } catch (error) {
        console.error('[WebSocketServer] Broadcast error:', error);
        failedClients.push(client);
      }
    });

    // 移除失败的客户端
    failedClients.forEach(client => {
      this.wsClients.delete(client);
      client.destroy();
    });
  }

  /**
   * 注册状态变化回调
   */
  onStateChange(callback: StateChangeCallback): () => void {
    this.stateCallbacks.add(callback);
    return () => {
      this.stateCallbacks.delete(callback);
    };
  }

  /**
   * 处理新连接
   */
  private handleConnection(socket: Socket): void {
    const clientAddress = `${socket.remoteAddress}:${socket.remotePort}`;
    console.log(`[WebSocketServer] New connection from ${clientAddress}`);

    let handshakeComplete = false;
    let isWebSocket = false;

    socket.on('data', (data: Uint8Array) => {
      if (!handshakeComplete) {
        const request = data.toString();

        // 检查是否是 WebSocket 升级请求
        if (request.includes('Upgrade: websocket')) {
          isWebSocket = true;
          this.handleWebSocketHandshake(socket, request);
          handshakeComplete = true;

          // 添加到客户端列表
          if (this.wsClients.size >= WEBSOCKET_SERVER_CONFIG.maxClients) {
            console.warn('[WebSocketServer] Max clients reached, closing new connection');
            socket.destroy();
            return;
          }

          this.wsClients.add(socket);
          console.log(`[WebSocketServer] WebSocket client added (total: ${this.wsClients.size})`);

          socket.on('close', () => {
            this.wsClients.delete(socket);
            console.log(`[WebSocketServer] Client disconnected (remaining: ${this.wsClients.size})`);
          });
        } else {
          // HTTP 请求
          this.handleHttpRequest(socket, request);
          socket.destroy(); // HTTP 请求处理后关闭连接
        }
      } else if (isWebSocket) {
        // WebSocket 帧数据（暂不处理客户端发送的消息）
        console.log('[WebSocketServer] Received WebSocket frame (ignored)');
      }
    });

    socket.on('error', (error: Error) => {
      console.error(`[WebSocketServer] Socket error from ${clientAddress}:`, error);
      this.wsClients.delete(socket);
    });

    socket.on('close', () => {
      this.wsClients.delete(socket);
    });
  }

  /**
   * 处理 HTTP 请求
   */
  private handleHttpRequest(socket: Socket, request: string): void {
    try {
      // 提取请求路径
      const lines = request.split('\r\n');
      const requestLine = lines[0];
      const path = requestLine.split(' ')[1] || '/';

      if (path === '/' || path === '/index.html') {
        // 返回 HTML 页面
        const html = this.getHtmlPage();
        const response =
          'HTTP/1.1 200 OK\r\n' +
          'Content-Type: text/html; charset=utf-8\r\n' +
          'Content-Length: ' + html.length + '\r\n' +
          'Connection: close\r\n\r\n' +
          html;
        socket.write(response);
      } else {
        // 404
        const response =
          'HTTP/1.1 404 Not Found\r\n' +
          'Content-Type: text/plain\r\n' +
          'Connection: close\r\n\r\n' +
          'Not Found';
        socket.write(response);
      }
    } catch (error) {
      console.error('[WebSocketServer] HTTP request error:', error);
    }
  }

  /**
   * 处理 WebSocket 握手
   */
  private handleWebSocketHandshake(socket: Socket, request: string): void {
    try {
      // 提取 Sec-WebSocket-Key
      const keyMatch = request.match(/Sec-WebSocket-Key: (.+)/);
      if (!keyMatch) {
        console.error('[WebSocketServer] Missing WebSocket key');
        socket.destroy();
        return;
      }

      const clientKey = keyMatch[1].trim();
      const acceptKey = this.computeAcceptKey(clientKey);

      const response =
        'HTTP/1.1 101 Switching Protocols\r\n' +
        'Upgrade: websocket\r\n' +
        'Connection: Upgrade\r\n' +
        `Sec-WebSocket-Accept: ${acceptKey}\r\n\r\n`;

      socket.write(response);
      console.log('[WebSocketServer] WebSocket handshake completed');
    } catch (error) {
      console.error('[WebSocketServer] WebSocket handshake error:', error);
    }
  }

  /**
   * 计算 WebSocket Accept Key
   */
  private computeAcceptKey(clientKey: string): string {
    // 注意：React Native 环境可能没有 crypto 模块
    // 这里使用一个简化的实现，实际可能需要引入 crypto 库
    const magic = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

    // 简化版本：使用 base64 编码（不完整，仅作为占位）
    // 实际需要 SHA-1 哈希
    const combined = clientKey + magic;

    // 对于完整实现，需要使用类似 'crypto-js' 的库
    // 这里先返回一个简单的 base64 编码
    return Buffer.from(combined).toString('base64').substring(0, 28);
  }

  /**
   * 创建 WebSocket 帧
   */
  private createWebSocketFrame(data: string): Uint8Array {
    const dataBuffer = Buffer.from(data, 'utf8');
    const frameLength = 2 + dataBuffer.length;
    const frame = Buffer.allocUnsafe(frameLength);

    // FIN + text frame
    frame[0] = 0x81;

    // Payload length (假设 < 126 字节)
    frame[1] = dataBuffer.length;

    // Payload data
    dataBuffer.copy(frame, 2);

    return frame;
  }

  /**
   * 获取 HTML 页面
   */
  private getHtmlPage(): string {
    return `<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Satori Eye - 读心结果</title>
  <style>
    :root {
      --bg-primary: #0D0015;
      --bg-secondary: #1A0028;
      --bg-surface: rgba(255, 0, 255, 0.05);
      --primary: #FF00FF;
      --primary-glow: rgba(255, 0, 255, 0.6);
      --secondary: #00FFFF;
      --secondary-glow: rgba(0, 255, 255, 0.8);
      --success: #00FF88;
      --error: #FF0044;
      --text: #FFFFFF;
      --text-secondary: rgba(255, 255, 255, 0.7);
      --text-muted: rgba(255, 255, 255, 0.5);
      --border: rgba(255, 0, 255, 0.3);
      --border-cyan: rgba(0, 255, 255, 0.3);
    }

    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }

    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Oxygen', 'Ubuntu', 'Cantarell', 'Fira Sans', 'Droid Sans', 'Helvetica Neue', sans-serif;
      background: var(--bg-primary);
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 20px;
      overflow: hidden;
      position: relative;
      -webkit-font-smoothing: antialiased;
      -moz-osx-font-smoothing: grayscale;
    }

    ::selection {
      background: rgba(255, 0, 255, 0.3);
      color: #FFFFFF;
    }

    .background-effects {
      position: fixed;
      top: 0;
      left: 0;
      right: 0;
      bottom: 0;
      z-index: 0;
      overflow: hidden;
    }

    .background-effects::before {
      content: '';
      position: absolute;
      top: -50%;
      left: -50%;
      right: -50%;
      bottom: -50%;
      background: radial-gradient(circle at 50% 50%, rgba(255, 0, 255, 0.15) 0%, transparent 50%),
                  radial-gradient(circle at 80% 20%, rgba(0, 255, 255, 0.1) 0%, transparent 40%),
                  radial-gradient(circle at 20% 80%, rgba(255, 0, 255, 0.1) 0%, transparent 40%);
      animation: gradientShift 15s ease-in-out infinite;
    }

    .background-effects::after {
      content: '';
      position: absolute;
      top: 0;
      left: 0;
      right: 0;
      bottom: 0;
      background-image:
        repeating-linear-gradient(0deg, transparent, transparent 2px, rgba(255, 0, 255, 0.03) 2px, rgba(255, 0, 255, 0.03) 4px),
        repeating-linear-gradient(90deg, transparent, transparent 2px, rgba(0, 255, 255, 0.03) 2px, rgba(0, 255, 255, 0.03) 4px);
      background-size: 50px 50px;
      opacity: 0.5;
      animation: gridScroll 20s linear infinite;
    }

    @keyframes gradientShift {
      0%, 100% { transform: translate(0, 0) rotate(0deg); }
      50% { transform: translate(10%, 10%) rotate(5deg); }
    }

    @keyframes gridScroll {
      0% { transform: translate(0, 0); }
      100% { transform: translate(50px, 50px); }
    }

    .particle {
      position: absolute;
      width: 2px;
      height: 2px;
      background: var(--primary);
      border-radius: 50%;
      box-shadow: 0 0 10px var(--primary-glow);
      animation: particleFloat 20s linear infinite;
      pointer-events: none;
    }

    .particle:nth-child(2n) {
      background: var(--secondary);
      box-shadow: 0 0 10px var(--secondary-glow);
      animation-duration: 25s;
    }

    @keyframes particleFloat {
      0% { transform: translateY(0) translateX(0); opacity: 0; }
      10% { opacity: 0.5; }
      90% { opacity: 0.5; }
      100% { transform: translateY(-100vh) translateX(50px); opacity: 0; }
    }

    .container {
      position: relative;
      z-index: 1;
      background: rgba(26, 0, 40, 0.7);
      backdrop-filter: blur(20px) saturate(180%);
      -webkit-backdrop-filter: blur(20px) saturate(180%);
      border: 1px solid rgba(255, 0, 255, 0.2);
      border-radius: 24px;
      box-shadow:
        0 8px 32px rgba(0, 0, 0, 0.4),
        0 0 0 1px rgba(255, 0, 255, 0.1) inset,
        0 0 60px rgba(255, 0, 255, 0.2),
        0 20px 80px rgba(0, 0, 0, 0.3);
      max-width: 700px;
      width: 100%;
      padding: 40px;
      animation: fadeInUp 0.6s ease-out 0.1s both;
    }

    @supports not (backdrop-filter: blur(20px)) {
      .container {
        background: rgba(26, 0, 40, 0.95);
      }
    }

    @keyframes fadeInUp {
      from {
        opacity: 0;
        transform: translateY(30px);
      }
      to {
        opacity: 1;
        transform: translateY(0);
      }
    }

    .logo-icon {
      width: 60px;
      height: 60px;
      margin: 0 auto 20px;
      position: relative;
    }

    .logo-icon::before,
    .logo-icon::after {
      content: '';
      position: absolute;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
      border-radius: 50%;
      border: 2px solid var(--primary);
    }

    .logo-icon::before {
      width: 100%;
      height: 100%;
      animation: eyePulse 2s ease-in-out infinite;
    }

    .logo-icon::after {
      width: 40%;
      height: 40%;
      background: var(--primary);
      box-shadow: 0 0 20px var(--primary-glow);
      animation: pupilDilate 3s ease-in-out infinite;
      border: none;
    }

    @keyframes eyePulse {
      0%, 100% {
        transform: translate(-50%, -50%) scale(1);
        opacity: 1;
      }
      50% {
        transform: translate(-50%, -50%) scale(1.1);
        opacity: 0.7;
      }
    }

    @keyframes pupilDilate {
      0%, 100% {
        width: 40%;
        height: 40%;
      }
      50% {
        width: 60%;
        height: 60%;
      }
    }

    h1 {
      color: var(--text);
      margin-bottom: 10px;
      font-size: 32px;
      font-weight: bold;
      letter-spacing: 2px;
      text-align: center;
      text-shadow: 0 0 20px var(--primary-glow), 0 0 40px var(--primary-glow);
      animation: fadeInUp 0.5s ease-out 0.2s both;
    }

    .subtitle {
      color: var(--secondary);
      margin-bottom: 32px;
      font-size: 14px;
      letter-spacing: 1px;
      text-align: center;
      animation: fadeInUp 0.5s ease-out 0.3s both;
    }

    .status-section {
      margin-bottom: 32px;
      text-align: center;
      animation: fadeInUp 0.5s ease-out 0.3s both;
    }

    .status {
      display: inline-block;
      padding: 8px 16px;
      border-radius: 20px;
      font-size: 12px;
      font-weight: bold;
      text-transform: uppercase;
      letter-spacing: 1.5px;
      position: relative;
      overflow: hidden;
      transition: all 0.3s ease;
    }

    .status.connected {
      background: rgba(0, 255, 136, 0.15);
      color: var(--success);
      border: 1px solid var(--success);
      box-shadow: 0 0 20px rgba(0, 255, 136, 0.3);
      animation: statusPulse 2s ease-in-out infinite;
    }

    .status.connected::before {
      content: '';
      position: absolute;
      top: 50%;
      left: 50%;
      width: 100%;
      height: 100%;
      background: radial-gradient(circle, rgba(0, 255, 136, 0.3) 0%, transparent 70%);
      animation: connectionRipple 2s ease-out infinite;
      transform: translate(-50%, -50%);
    }

    .status.disconnected {
      background: rgba(255, 0, 68, 0.15);
      color: var(--error);
      border: 1px solid var(--error);
    }

    @keyframes statusPulse {
      0%, 100% {
        transform: scale(1);
        opacity: 1;
      }
      50% {
        transform: scale(1.05);
        opacity: 0.8;
      }
    }

    @keyframes connectionRipple {
      0% {
        transform: translate(-50%, -50%) scale(0.8);
        opacity: 1;
      }
      100% {
        transform: translate(-50%, -50%) scale(2);
        opacity: 0;
      }
    }

    .result-section {
      animation: fadeInUp 0.5s ease-out 0.4s both;
    }

    .result-container {
      background: linear-gradient(var(--bg-secondary), var(--bg-secondary)) padding-box,
                  linear-gradient(135deg, var(--primary), var(--secondary)) border-box;
      border: 2px solid transparent;
      border-radius: 16px;
      padding: 24px;
      min-height: 200px;
      margin-bottom: 16px;
      box-shadow:
        0 4px 16px rgba(0, 0, 0, 0.3),
        0 0 20px var(--primary-glow),
        inset 0 0 20px rgba(255, 0, 255, 0.05);
      position: relative;
      overflow: hidden;
    }

    .result-container.active {
      animation: borderGlow 2s ease-in-out;
    }

    @keyframes borderGlow {
      0%, 100% {
        box-shadow:
          0 4px 16px rgba(0, 0, 0, 0.3),
          0 0 20px var(--primary-glow),
          inset 0 0 20px rgba(255, 0, 255, 0.1);
      }
      50% {
        box-shadow:
          0 4px 16px rgba(0, 0, 0, 0.3),
          0 0 40px var(--secondary-glow),
          0 0 60px var(--secondary-glow),
          inset 0 0 30px rgba(0, 255, 255, 0.2);
      }
    }

    #result {
      color: var(--text);
      font-size: 18px;
      line-height: 1.8;
      letter-spacing: 0.5px;
      white-space: pre-wrap;
      word-wrap: break-word;
      max-height: 400px;
      overflow-y: auto;
      scroll-behavior: smooth;
      will-change: opacity, transform;
      transition: opacity 0.3s ease, transform 0.3s ease;
    }

    #result::-webkit-scrollbar {
      width: 8px;
    }

    #result::-webkit-scrollbar-track {
      background: rgba(255, 0, 255, 0.05);
      border-radius: 4px;
    }

    #result::-webkit-scrollbar-thumb {
      background: linear-gradient(180deg, var(--primary), var(--secondary));
      border-radius: 4px;
      box-shadow: 0 0 10px var(--primary-glow);
    }

    #result::-webkit-scrollbar-thumb:hover {
      background: linear-gradient(180deg, var(--secondary), var(--primary));
    }

    .loading-container {
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      min-height: 150px;
      gap: 20px;
    }

    .neural-pulse {
      position: relative;
      width: 80px;
      height: 80px;
    }

    .pulse-ring {
      position: absolute;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
      width: 20px;
      height: 20px;
      border: 2px solid var(--primary);
      border-radius: 50%;
      animation: neuralPulse 2s ease-out infinite;
    }

    .pulse-ring:nth-child(2) {
      border-color: var(--secondary);
      animation-delay: 0.4s;
    }

    .pulse-ring:nth-child(3) {
      border-color: var(--primary);
      animation-delay: 0.8s;
    }

    @keyframes neuralPulse {
      0% {
        width: 20px;
        height: 20px;
        opacity: 1;
      }
      100% {
        width: 80px;
        height: 80px;
        opacity: 0;
      }
    }

    .loading-text {
      color: var(--text-secondary);
      font-size: 16px;
      letter-spacing: 2px;
    }

    .loading-text .dot {
      animation: dotPulse 1.5s ease-in-out infinite;
    }

    .loading-text .dot:nth-child(2) {
      animation-delay: 0.2s;
    }

    .loading-text .dot:nth-child(3) {
      animation-delay: 0.4s;
    }

    .loading-text .dot:nth-child(4) {
      animation-delay: 0.6s;
    }

    @keyframes dotPulse {
      0%, 80%, 100% {
        opacity: 0.3;
        transform: scale(0.8);
      }
      40% {
        opacity: 1;
        transform: scale(1);
      }
    }

    .timestamp {
      color: var(--text-muted);
      font-size: 11px;
      font-family: 'Courier New', monospace;
      text-align: right;
      letter-spacing: 0.5px;
      transition: opacity 0.3s ease;
    }

    @media (hover: hover) {
      .container:hover {
        transform: translateY(-4px);
        box-shadow:
          0 12px 48px rgba(0, 0, 0, 0.5),
          0 0 0 1px rgba(255, 0, 255, 0.2) inset,
          0 0 80px rgba(255, 0, 255, 0.3),
          0 24px 100px rgba(0, 0, 0, 0.4);
        transition: transform 0.3s ease, box-shadow 0.3s ease;
      }
    }

    @media (max-width: 768px) {
      .container {
        max-width: 90%;
        padding: 30px;
        margin: 20px auto;
      }

      h1 {
        font-size: 28px;
      }

      #result {
        font-size: 16px;
      }
    }

    @media (max-width: 480px) {
      body {
        padding: 10px;
      }

      .container {
        max-width: 100%;
        padding: 20px;
        margin: 10px auto;
        border-radius: 16px;
      }

      h1 {
        font-size: 24px;
        letter-spacing: 1px;
      }

      .subtitle {
        font-size: 12px;
      }

      #result {
        font-size: 15px;
        line-height: 1.6;
      }

      .logo-icon {
        width: 50px;
        height: 50px;
      }
    }

    @media (prefers-reduced-motion: reduce) {
      * {
        animation-duration: 0.01ms !important;
        animation-iteration-count: 1 !important;
        transition-duration: 0.01ms !important;
      }
    }
  </style>
</head>
<body>
  <div class="background-effects">
    <div class="particle" style="left: 10%; animation-delay: 0s;"></div>
    <div class="particle" style="left: 20%; animation-delay: -2s;"></div>
    <div class="particle" style="left: 30%; animation-delay: -4s;"></div>
    <div class="particle" style="left: 40%; animation-delay: -6s;"></div>
    <div class="particle" style="left: 50%; animation-delay: -8s;"></div>
    <div class="particle" style="left: 60%; animation-delay: -10s;"></div>
    <div class="particle" style="left: 70%; animation-delay: -12s;"></div>
    <div class="particle" style="left: 80%; animation-delay: -14s;"></div>
    <div class="particle" style="left: 90%; animation-delay: -16s;"></div>
    <div class="particle" style="left: 15%; animation-delay: -3s;"></div>
    <div class="particle" style="left: 25%; animation-delay: -5s;"></div>
    <div class="particle" style="left: 35%; animation-delay: -7s;"></div>
    <div class="particle" style="left: 45%; animation-delay: -9s;"></div>
    <div class="particle" style="left: 55%; animation-delay: -11s;"></div>
    <div class="particle" style="left: 65%; animation-delay: -13s;"></div>
    <div class="particle" style="left: 75%; animation-delay: -15s;"></div>
    <div class="particle" style="left: 85%; animation-delay: -17s;"></div>
    <div class="particle" style="left: 95%; animation-delay: -19s;"></div>
    <div class="particle" style="left: 5%; animation-delay: -1s;"></div>
    <div class="particle" style="left: 50%; animation-delay: -18s;"></div>
  </div>

  <div class="container">
    <div class="logo-icon"></div>
    <h1>Satori Eye</h1>
    <p class="subtitle">实时 AI 心理分析 · NEURAL INTERFACE</p>

    <div class="status-section">
      <div id="status" class="status disconnected">未连接</div>
    </div>

    <div class="result-section">
      <div class="result-container" id="resultContainer">
        <div id="result">
          <div class="loading-container">
            <div class="neural-pulse">
              <div class="pulse-ring"></div>
              <div class="pulse-ring"></div>
              <div class="pulse-ring"></div>
            </div>
            <div class="loading-text">
              <span>等待连接</span><span class="dot">.</span><span class="dot">.</span><span class="dot">.</span>
            </div>
          </div>
        </div>
      </div>
      <div class="timestamp" id="timestamp"></div>
    </div>
  </div>

  <script>
    const ws = new WebSocket('ws://' + location.host + '/ws');
    const statusEl = document.getElementById('status');
    const resultEl = document.getElementById('result');
    const resultContainer = document.getElementById('resultContainer');
    const timestampEl = document.getElementById('timestamp');

    function showLoading() {
      resultEl.innerHTML = \`
        <div class="loading-container">
          <div class="neural-pulse">
            <div class="pulse-ring"></div>
            <div class="pulse-ring"></div>
            <div class="pulse-ring"></div>
          </div>
          <div class="loading-text">
            <span>分析中</span><span class="dot">.</span><span class="dot">.</span><span class="dot">.</span>
          </div>
        </div>
      \`;
    }

    function updateConnectionState(connected) {
      statusEl.style.transform = 'scale(0.9)';
      statusEl.style.opacity = '0';

      setTimeout(() => {
        statusEl.className = 'status ' + (connected ? 'connected' : 'disconnected');
        statusEl.textContent = connected ? '已连接' : '未连接';
        statusEl.style.transform = 'scale(1)';
        statusEl.style.opacity = '1';
      }, 150);
    }

    ws.onopen = function() {
      updateConnectionState(true);
      resultEl.innerHTML = \`
        <div class="loading-container">
          <div class="neural-pulse">
            <div class="pulse-ring"></div>
            <div class="pulse-ring"></div>
            <div class="pulse-ring"></div>
          </div>
          <div class="loading-text">
            <span>等待数据</span><span class="dot">.</span><span class="dot">.</span><span class="dot">.</span>
          </div>
        </div>
      \`;
    };

    ws.onmessage = function(event) {
      const data = JSON.parse(event.data);

      resultEl.style.opacity = '0';
      resultEl.style.transform = 'translateX(-20px)';

      setTimeout(() => {
        resultEl.textContent = data.analysis;
        resultEl.style.opacity = '1';
        resultEl.style.transform = 'translateX(0)';

        const date = new Date(data.timestamp);
        timestampEl.textContent = '更新时间: ' + date.toLocaleString('zh-CN');
        timestampEl.style.opacity = '0';
        setTimeout(() => {
          timestampEl.style.opacity = '1';
        }, 300);

        resultContainer.classList.add('active');
        setTimeout(() => {
          resultContainer.classList.remove('active');
        }, 2000);
      }, 300);
    };

    ws.onclose = function() {
      updateConnectionState(false);
      resultEl.style.opacity = '0';
      setTimeout(() => {
        resultEl.innerHTML = \`
          <div class="loading-container">
            <div class="loading-text">
              <span>连接断开</span>
            </div>
          </div>
        \`;
        resultEl.style.opacity = '1';
      }, 300);
    };

    ws.onerror = function(error) {
      console.error('WebSocket error:', error);
      updateConnectionState(false);
      statusEl.textContent = '连接错误';
    };
  </script>
</body>
</html>`;
  }

  /**
   * 获取本机 IP 地址
   */
  private async getLocalIpAddress(): Promise<void> {
    try {
      // React Native 获取 IP 地址需要使用第三方库
      // 这里使用占位符，用户需要手动查看设备 IP
      this.serverUrl = `http://DEVICE_IP:${this.port}`;
      console.log(`[WebSocketServer] Server URL will be: http://<device-ip>:${this.port}`);
    } catch (error) {
      console.error('[WebSocketServer] Failed to get local IP:', error);
    }
  }

  /**
   * 通知状态变化
   */
  private notifyStateChange(running: boolean, url: string | null): void {
    this.stateCallbacks.forEach(callback => {
      try {
        callback(running, url);
      } catch (error) {
        console.error('[WebSocketServer] Error in state callback:', error);
      }
    });
  }
}
