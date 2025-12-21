import {VideoFrame} from '../types';

/**
 * 视频帧分片信息
 */
interface FrameFragment {
  fragments: Uint8Array[];
  totalFragments: number;
  receivedCount: number;
  timestamp: number;
  width: number;
  height: number;
}

/**
 * 视频流统计信息
 */
export interface VideoStreamStats {
  droppedFrames: number;
  receivedFrames: number;
  avgLatency: number;
  currentFPS: number;
}

/**
 * 视频流接收器
 * 负责接收 UDP 视频分片并重组为完整帧
 */
export class VideoStreamReceiver {
  private bufferPool: Uint8Array[] = [];
  private availableBuffers: Uint8Array[] = [];
  private fragmentMap: Map<number, FrameFragment> = new Map();

  // 统计信息
  private droppedFrames: number = 0;
  private receivedFrames: number = 0;
  private latencies: number[] = [];
  private frameTimestamps: number[] = [];

  // 配置
  private readonly bufferSize: number;
  private readonly frameTimeout: number = 1000; // 1秒超时
  private readonly maxCachedFrames: number = 5;

  // 回调
  private onFrameComplete: ((frame: VideoFrame) => void) | null = null;

  /**
   * 构造函数
   * @param bufferPoolSize 缓冲区池大小
   * @param bufferSize 单个缓冲区大小（字节）
   */
  constructor(bufferPoolSize: number = 10, bufferSize: number = 200 * 1024) {
    this.bufferSize = bufferSize;

    // 预分配缓冲区池
    for (let i = 0; i < bufferPoolSize; i++) {
      const buffer = new Uint8Array(bufferSize);
      this.bufferPool.push(buffer);
      this.availableBuffers.push(buffer);
    }

    // 定期清理超时帧
    this.startCleanupTimer();
  }

  /**
   * 设置帧完成回调
   */
  setFrameCallback(callback: (frame: VideoFrame) => void): void {
    this.onFrameComplete = callback;
  }

  /**
   * 接收单个分片
   * @param frameId 帧 ID
   * @param fragmentIndex 分片索引
   * @param totalFragments 总分片数
   * @param data 分片数据
   * @param width 视频宽度
   * @param height 视频高度
   */
  onFragment(
    frameId: number,
    fragmentIndex: number,
    totalFragments: number,
    data: Uint8Array,
    width: number,
    height: number,
  ): void {
    // 获取或创建帧信息
    let frameInfo = this.fragmentMap.get(frameId);
    if (!frameInfo) {
      frameInfo = {
        fragments: new Array(totalFragments),
        totalFragments,
        receivedCount: 0,
        timestamp: Date.now(),
        width,
        height,
      };
      this.fragmentMap.set(frameId, frameInfo);
    }

    // 检查分片是否已存在（防止重复）
    if (frameInfo.fragments[fragmentIndex]) {
      return;
    }

    // 获取缓冲区并复制数据
    const buffer = this.acquireBuffer();
    if (!buffer) {
      console.warn('VideoStreamReceiver: No available buffer');
      return;
    }

    // 使用 subarray 避免复制（性能优化）
    buffer.set(data.subarray(0, data.length));
    frameInfo.fragments[fragmentIndex] = buffer.subarray(0, data.length);
    frameInfo.receivedCount++;

    // 检查是否收集完整
    if (frameInfo.receivedCount === frameInfo.totalFragments) {
      this.assembleFrame(frameId, frameInfo);
    }
  }

  /**
   * 组装完整帧
   */
  private assembleFrame(frameId: number, frameInfo: FrameFragment): void {
    // 计算总大小
    let totalSize = 0;
    for (const fragment of frameInfo.fragments) {
      if (fragment) {
        totalSize += fragment.length;
      }
    }

    // 组装数据
    const completeData = new Uint8Array(totalSize);
    let offset = 0;
    for (const fragment of frameInfo.fragments) {
      if (fragment) {
        completeData.set(fragment, offset);
        offset += fragment.length;
        // 释放缓冲区
        this.releaseBuffer(fragment);
      }
    }

    // 创建完整帧对象
    const frame: VideoFrame = {
      frameId,
      data: completeData,
      timestamp: frameInfo.timestamp,
      width: frameInfo.width,
      height: frameInfo.height,
    };

    // 更新统计
    const now = Date.now();
    const latency = now - frameInfo.timestamp;
    this.latencies.push(latency);
    this.frameTimestamps.push(now);
    this.receivedFrames++;

    // 限制统计数据大小
    if (this.latencies.length > 60) {
      this.latencies.shift();
    }
    if (this.frameTimestamps.length > 60) {
      this.frameTimestamps.shift();
    }

    // 从映射中移除
    this.fragmentMap.delete(frameId);

    // 触发回调
    this.onFrameComplete?.(frame);
  }

  /**
   * 获取完整帧（如果准备好）
   * @param frameId 帧 ID
   */
  getCompleteFrame(frameId: number): VideoFrame | null {
    const frameInfo = this.fragmentMap.get(frameId);
    if (!frameInfo || frameInfo.receivedCount !== frameInfo.totalFragments) {
      return null;
    }

    this.assembleFrame(frameId, frameInfo);
    return null; // 帧已通过回调发送
  }

  /**
   * 从缓冲区池获取一个可用缓冲区
   */
  private acquireBuffer(): Uint8Array | null {
    return this.availableBuffers.pop() || null;
  }

  /**
   * 释放缓冲区回池
   */
  private releaseBuffer(buffer: Uint8Array): void {
    // 只释放属于池的缓冲区
    if (this.bufferPool.includes(buffer)) {
      this.availableBuffers.push(buffer);
    }
  }

  /**
   * 清理超时帧
   */
  private cleanup(): void {
    const now = Date.now();
    const toDelete: number[] = [];

    this.fragmentMap.forEach((frameInfo, frameId) => {
      if (now - frameInfo.timestamp > this.frameTimeout) {
        // 释放所有分片的缓冲区
        frameInfo.fragments.forEach(fragment => {
          if (fragment) {
            this.releaseBuffer(fragment);
          }
        });
        toDelete.push(frameId);
        this.droppedFrames++;
      }
    });

    toDelete.forEach(frameId => this.fragmentMap.delete(frameId));

    // 限制缓存帧数量
    if (this.fragmentMap.size > this.maxCachedFrames) {
      const sortedFrames = Array.from(this.fragmentMap.entries()).sort(
        (a, b) => a[1].timestamp - b[1].timestamp,
      );

      // 删除最旧的帧
      const toRemove = sortedFrames.slice(0, this.fragmentMap.size - this.maxCachedFrames);
      toRemove.forEach(([frameId, frameInfo]) => {
        frameInfo.fragments.forEach(fragment => {
          if (fragment) {
            this.releaseBuffer(fragment);
          }
        });
        this.fragmentMap.delete(frameId);
        this.droppedFrames++;
      });
    }
  }

  /**
   * 启动清理定时器
   */
  private startCleanupTimer(): void {
    setInterval(() => {
      this.cleanup();
    }, 500); // 每 500ms 清理一次
  }

  /**
   * 获取统计信息
   */
  getStats(): VideoStreamStats {
    // 计算 FPS
    let currentFPS = 0;
    if (this.frameTimestamps.length >= 2) {
      const duration =
        this.frameTimestamps[this.frameTimestamps.length - 1] - this.frameTimestamps[0];
      currentFPS = ((this.frameTimestamps.length - 1) / duration) * 1000;
    }

    // 计算平均延迟
    const avgLatency =
      this.latencies.length > 0
        ? this.latencies.reduce((sum, l) => sum + l, 0) / this.latencies.length
        : 0;

    return {
      droppedFrames: this.droppedFrames,
      receivedFrames: this.receivedFrames,
      avgLatency,
      currentFPS,
    };
  }

  /**
   * 重置统计信息
   */
  resetStats(): void {
    this.droppedFrames = 0;
    this.receivedFrames = 0;
    this.latencies = [];
    this.frameTimestamps = [];
  }

  /**
   * 销毁接收器
   */
  destroy(): void {
    // 清理所有帧
    this.fragmentMap.forEach(frameInfo => {
      frameInfo.fragments.forEach(fragment => {
        if (fragment) {
          this.releaseBuffer(fragment);
        }
      });
    });
    this.fragmentMap.clear();
    this.onFrameComplete = null;
  }
}
