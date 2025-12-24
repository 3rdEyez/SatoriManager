/**
 * Face Capture Manager
 * 管理人脸追踪稳定性检测和帧捕获逻辑
 */

import { FaceDetectionResult } from './FaceDetector';
import { VideoFrame } from '../types';

type CaptureCallback = (trigger: { trackingId: number; stabilityDuration: number; frame: VideoFrame }) => void;

/**
 * Face Capture Manager Class
 */
export class FaceCaptureManager {
  private currentTrackingId: number | null = null;
  private trackingStartTime: number = 0;
  private lastCaptureTime: number = 0;
  private stabilityThreshold: number;
  private minCaptureInterval: number;
  private captureCallback: CaptureCallback | null = null;
  private currentFrame: VideoFrame | null = null;

  constructor(stabilityThreshold: number = 1000, minCaptureInterval: number = 10000) {
    this.stabilityThreshold = stabilityThreshold;
    this.minCaptureInterval = minCaptureInterval;
  }

  /**
   * 设置配置
   */
  setConfig(stabilityThreshold: number, minCaptureInterval: number): void {
    this.stabilityThreshold = stabilityThreshold;
    this.minCaptureInterval = minCaptureInterval;
    console.log(`[FaceCaptureManager] Config updated: threshold=${stabilityThreshold}ms, interval=${minCaptureInterval}ms`);
  }

  /**
   * 注册捕获回调
   */
  onCapture(callback: CaptureCallback): void {
    this.captureCallback = callback;
  }

  /**
   * 处理人脸检测结果
   */
  onFaceDetected(result: FaceDetectionResult, frame: VideoFrame): void {
    const now = Date.now();

    // 保存当前帧引用
    this.currentFrame = frame;

    // 如果没有检测到人脸，重置追踪状态
    if (result.faces.length === 0) {
      this.resetTracking();
      return;
    }

    // 选择目标人脸（优先选择有 trackingId 的人脸，然后选择最大的人脸）
    const targetFace = this.selectTargetFace(result.faces);

    if (!targetFace || targetFace.trackingId === undefined) {
      // 没有有效的 trackingId，重置
      this.resetTracking();
      return;
    }

    // 检查是否是新的 trackingId
    if (targetFace.trackingId !== this.currentTrackingId) {
      // 新的人脸，重置追踪
      this.currentTrackingId = targetFace.trackingId;
      this.trackingStartTime = now;
      console.log(`[FaceCaptureManager] New tracking ID: ${targetFace.trackingId}`);
      return;
    }

    // 计算稳定时长
    const stabilityDuration = now - this.trackingStartTime;

    // 检查是否达到阈值
    if (stabilityDuration >= this.stabilityThreshold) {
      // 检查距上次捕获的时间间隔
      const timeSinceLastCapture = now - this.lastCaptureTime;

      if (timeSinceLastCapture >= this.minCaptureInterval) {
        // 触发捕获
        this.triggerCapture(targetFace.trackingId, stabilityDuration, frame);
        this.lastCaptureTime = now;

        // 重置追踪开始时间，防止连续触发
        this.trackingStartTime = now;
      }
    }
  }

  /**
   * 选择目标人脸
   */
  private selectTargetFace(faces: FaceDetectionResult['faces']): FaceDetectionResult['faces'][0] | null {
    if (faces.length === 0) {
      return null;
    }

    // 如果有当前的 trackingId，优先选择同一个人
    if (this.currentTrackingId !== null) {
      const trackedFace = faces.find(face => face.trackingId === this.currentTrackingId);
      if (trackedFace) {
        return trackedFace;
      }
    }

    // 否则选择最大的人脸
    return faces.reduce((largest, current) => {
      const largestArea = largest.boundingBox.width * largest.boundingBox.height;
      const currentArea = current.boundingBox.width * current.boundingBox.height;
      return currentArea > largestArea ? current : largest;
    });
  }

  /**
   * 触发捕获
   */
  private triggerCapture(trackingId: number, stabilityDuration: number, frame: VideoFrame): void {
    console.log(`[FaceCaptureManager] Capture triggered: trackingId=${trackingId}, stability=${stabilityDuration}ms`);

    if (this.captureCallback) {
      try {
        this.captureCallback({
          trackingId,
          stabilityDuration,
          frame,
        });
      } catch (error) {
        console.error('[FaceCaptureManager] Error in capture callback:', error);
      }
    }
  }

  /**
   * 重置追踪状态
   */
  private resetTracking(): void {
    if (this.currentTrackingId !== null) {
      console.log(`[FaceCaptureManager] Reset tracking (was: ${this.currentTrackingId})`);
    }
    this.currentTrackingId = null;
    this.trackingStartTime = 0;
  }

  /**
   * 手动重置
   */
  reset(): void {
    this.resetTracking();
    this.lastCaptureTime = 0;
    this.currentFrame = null;
  }

  /**
   * 获取当前稳定时长
   */
  getStability(): number {
    if (this.currentTrackingId === null || this.trackingStartTime === 0) {
      return 0;
    }
    return Date.now() - this.trackingStartTime;
  }

  /**
   * 获取当前 trackingId
   */
  getCurrentTrackingId(): number | null {
    return this.currentTrackingId;
  }

  /**
   * 检查是否正在追踪
   */
  isTracking(): boolean {
    return this.currentTrackingId !== null;
  }

  /**
   * 获取进度（0-1，相对于阈值）
   */
  getProgress(): number {
    const stability = this.getStability();
    return Math.min(stability / this.stabilityThreshold, 1);
  }
}
