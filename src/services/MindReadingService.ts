/**
 * Mind Reading Service
 * 读心功能主服务 - 协调所有组件
 */

import { FaceCaptureManager } from './FaceCaptureManager';
import { QianwenClient } from './QianwenClient';
import { WebSocketServer } from './WebSocketServer';
import { MindReadingConfig, MindReadingState, MindReadingResult } from '../types';
import { MIND_READING_DEFAULTS } from '../constants/MindReadingDefaults';
import { FaceDetectionResult } from './FaceDetector';
import { VideoFrame } from '../types';

type StateChangeCallback = (state: Partial<MindReadingState>) => void;

/**
 * Mind Reading Service Class
 */
export class MindReadingService {
  private faceCaptureManager: FaceCaptureManager;
  private qianwenClient: QianwenClient;
  private webSocketServer: WebSocketServer;
  private config: MindReadingConfig;
  private state: MindReadingState;
  private stateCallbacks: Set<StateChangeCallback> = new Set();
  private isInitialized: boolean = false;
  private isRunning: boolean = false;

  constructor() {
    this.config = {...MIND_READING_DEFAULTS};
    this.state = {
      isCapturing: false,
      isAnalyzing: false,
      isServerRunning: false,
      serverUrl: null,
      lastResult: null,
      currentStability: 0,
      currentTrackingId: null,
      error: null,
    };

    // 初始化组件
    this.faceCaptureManager = new FaceCaptureManager(
      this.config.stabilityThreshold,
      this.config.minCaptureInterval,
    );
    this.qianwenClient = new QianwenClient(this.config.qianwenApiKey);
    this.webSocketServer = new WebSocketServer();

    // 设置回调
    this.setupCallbacks();
  }

  /**
   * 初始化服务
   */
  async initialize(config: MindReadingConfig): Promise<void> {
    console.log('[MindReadingService] Initializing...');

    this.config = {...this.config, ...config};

    // 更新组件配置
    this.faceCaptureManager.setConfig(
      this.config.stabilityThreshold,
      this.config.minCaptureInterval,
    );
    this.qianwenClient.setApiKey(this.config.qianwenApiKey);

    this.isInitialized = true;
    console.log('[MindReadingService] Initialized successfully');
  }

  /**
   * 启动服务
   */
  async start(): Promise<void> {
    if (!this.isInitialized) {
      throw new Error('Service not initialized. Call initialize() first.');
    }

    if (this.isRunning) {
      console.log('[MindReadingService] Already running');
      return;
    }

    console.log('[MindReadingService] Starting...');

    this.isRunning = true;

    // 启动 WebSocket 服务器
    try {
      const serverUrl = await this.webSocketServer.start(this.config.serverPort);
      this.updateState({
        isServerRunning: true,
        serverUrl,
      });
      console.log('[MindReadingService] WebSocket server started:', serverUrl);
    } catch (error) {
      console.error('[MindReadingService] Failed to start WebSocket server:', error);
      this.updateState({
        error: 'Failed to start server: ' + (error as Error).message,
      });
      throw error;
    }
  }

  /**
   * 停止服务
   */
  stop(): void {
    if (!this.isRunning) {
      return;
    }

    console.log('[MindReadingService] Stopping...');

    // 停止 WebSocket 服务器
    this.webSocketServer.stop();

    // 重置状态
    this.isRunning = false;
    this.faceCaptureManager.reset();

    this.updateState({
      isServerRunning: false,
      serverUrl: null,
      isCapturing: false,
      isAnalyzing: false,
      currentStability: 0,
      currentTrackingId: null,
    });

    console.log('[MindReadingService] Stopped');
  }

  /**
   * 更新配置
   */
  updateConfig(config: Partial<MindReadingConfig>): void {
    this.config = {...this.config, ...config};

    // 更新组件配置
    if (config.stabilityThreshold !== undefined || config.minCaptureInterval !== undefined) {
      this.faceCaptureManager.setConfig(
        this.config.stabilityThreshold,
        this.config.minCaptureInterval,
      );
    }

    if (config.qianwenApiKey !== undefined) {
      this.qianwenClient.setApiKey(this.config.qianwenApiKey);
    }

    console.log('[MindReadingService] Config updated:', config);
  }

  /**
   * 处理视频帧（从 VisionScreen 调用）
   */
  processFrame(frame: VideoFrame, faceResult: FaceDetectionResult): void {
    if (!this.isRunning) {
      return;
    }

    // 更新追踪状态
    this.updateState({
      currentTrackingId: this.faceCaptureManager.getCurrentTrackingId(),
      currentStability: this.faceCaptureManager.getStability(),
    });

    // 传递给人脸捕获管理器
    this.faceCaptureManager.onFaceDetected(faceResult, frame);
  }

  /**
   * 获取状态
   */
  getState(): MindReadingState {
    return {...this.state};
  }

  /**
   * 获取配置
   */
  getConfig(): MindReadingConfig {
    return {...this.config};
  }

  /**
   * 获取服务器 URL
   */
  getServerUrl(): string | null {
    return this.webSocketServer.getServerUrl();
  }

  /**
   * 检查是否正在运行
   */
  isActive(): boolean {
    return this.isRunning;
  }

  /**
   * 检查是否已初始化
   */
  isServiceInitialized(): boolean {
    return this.isInitialized;
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
   * 获取 WebSocket 服务器实例（用于外部控制）
   */
  getWebSocketServer(): WebSocketServer {
    return this.webSocketServer;
  }

  /**
   * 获取人脸捕获管理器（用于状态显示）
   */
  getFaceCaptureManager(): FaceCaptureManager {
    return this.faceCaptureManager;
  }

  /**
   * 设置回调
   */
  private setupCallbacks(): void {
    // 人脸捕获回调
    this.faceCaptureManager.onCapture(async ({ trackingId, stabilityDuration, frame }) => {
      console.log(`[MindReadingService] Capture triggered: trackingId=${trackingId}`);

      this.updateState({
        isCapturing: true,
        isAnalyzing: true,
      });

      try {
        // 调用千问 API 分析
        const result = await this.qianwenClient.analyzeImage(
          frame.data,
          this.config.customPrompt,
        );

        console.log('[MindReadingService] Analysis completed:', result.analysis);

        // 广播到 WebSocket 客户端
        this.webSocketServer.broadcast(result);

        // 更新状态
        this.updateState({
          isCapturing: false,
          isAnalyzing: false,
          lastResult: result,
          error: null,
        });
      } catch (error) {
        console.error('[MindReadingService] Analysis failed:', error);
        this.updateState({
          isCapturing: false,
          isAnalyzing: false,
          error: (error as Error).message,
        });
      }
    });

    // WebSocket 服务器状态回调
    this.webSocketServer.onStateChange((running, url) => {
      this.updateState({
        isServerRunning: running,
        serverUrl: url,
      });
    });

    // 千问 API 错误回调
    this.qianwenClient.onError((error) => {
      console.error('[MindReadingService] Qianwen API error:', error);
      this.updateState({
        error: error.message,
      });
    });
  }

  /**
   * 更新状态并通知回调
   */
  private updateState(partialState: Partial<MindReadingState>): void {
    this.state = {...this.state, ...partialState};

    this.stateCallbacks.forEach(callback => {
      try {
        callback(partialState);
      } catch (error) {
        console.error('[MindReadingService] Error in state callback:', error);
      }
    });
  }
}

// Singleton instance
let mindReadingServiceInstance: MindReadingService | null = null;

/**
 * Get the singleton instance of MindReadingService
 */
export function getMindReadingService(): MindReadingService {
  if (!mindReadingServiceInstance) {
    mindReadingServiceInstance = new MindReadingService();
  }
  return mindReadingServiceInstance;
}
