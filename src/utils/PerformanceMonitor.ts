/**
 * 性能监控统计
 */
export interface PerformanceStats {
  fps: number;
  avgLatency: number;
  p50Latency: number;
  p95Latency: number;
  p99Latency: number;
  minLatency: number;
  maxLatency: number;
  frameCount: number;
  droppedFrames: number;
}

/**
 * 性能监控器
 * 用于测量端到端延迟、FPS、丢包率等性能指标
 */
export class PerformanceMonitor {
  private frameTimestamps: number[] = [];
  private latencies: number[] = [];
  private droppedFrames: number = 0;
  private totalFrames: number = 0;
  private maxSamples: number;
  private lastFrameTime: number = 0;
  private expectedFrameInterval: number;

  /**
   * @param maxSamples 最多保留多少帧的统计数据
   * @param expectedFPS 预期 FPS（用于计算丢帧）
   */
  constructor(maxSamples: number = 60, expectedFPS: number = 30) {
    this.maxSamples = maxSamples;
    this.expectedFrameInterval = 1000 / expectedFPS;
  }

  /**
   * 记录一帧
   * @param captureTime 帧捕获时间（毫秒）
   * @param displayTime 帧显示时间（毫秒），默认为当前时间
   */
  recordFrame(captureTime: number, displayTime: number = Date.now()): void {
    this.totalFrames++;

    // 计算延迟
    const latency = displayTime - captureTime;
    this.latencies.push(latency);

    // 记录时间戳
    this.frameTimestamps.push(displayTime);

    // 检测丢帧
    if (this.lastFrameTime > 0) {
      const interval = displayTime - this.lastFrameTime;
      // 如果间隔大于预期的 1.5 倍，认为丢帧
      if (interval > this.expectedFrameInterval * 1.5) {
        const droppedCount = Math.floor(
          interval / this.expectedFrameInterval,
        ) - 1;
        this.droppedFrames += droppedCount;
      }
    }

    this.lastFrameTime = displayTime;

    // 限制样本数量
    if (this.frameTimestamps.length > this.maxSamples) {
      this.frameTimestamps.shift();
    }
    if (this.latencies.length > this.maxSamples) {
      this.latencies.shift();
    }
  }

  /**
   * 获取当前 FPS
   */
  getFPS(): number {
    if (this.frameTimestamps.length < 2) {
      return 0;
    }

    const firstTimestamp = this.frameTimestamps[0];
    const lastTimestamp = this.frameTimestamps[this.frameTimestamps.length - 1];
    const duration = lastTimestamp - firstTimestamp;

    if (duration === 0) {
      return 0;
    }

    return ((this.frameTimestamps.length - 1) / duration) * 1000;
  }

  /**
   * 获取平均延迟（毫秒）
   */
  getAvgLatency(): number {
    if (this.latencies.length === 0) {
      return 0;
    }

    const sum = this.latencies.reduce((acc, latency) => acc + latency, 0);
    return sum / this.latencies.length;
  }

  /**
   * 获取延迟百分位数
   * @param percentile 百分位（0-1）
   */
  getLatencyPercentile(percentile: number): number {
    if (this.latencies.length === 0) {
      return 0;
    }

    const sorted = [...this.latencies].sort((a, b) => a - b);
    const index = Math.floor(sorted.length * percentile);
    return sorted[Math.min(index, sorted.length - 1)];
  }

  /**
   * 获取 P50 延迟（中位数）
   */
  getP50Latency(): number {
    return this.getLatencyPercentile(0.5);
  }

  /**
   * 获取 P95 延迟
   */
  getP95Latency(): number {
    return this.getLatencyPercentile(0.95);
  }

  /**
   * 获取 P99 延迟
   */
  getP99Latency(): number {
    return this.getLatencyPercentile(0.99);
  }

  /**
   * 获取最小延迟
   */
  getMinLatency(): number {
    if (this.latencies.length === 0) {
      return 0;
    }
    return Math.min(...this.latencies);
  }

  /**
   * 获取最大延迟
   */
  getMaxLatency(): number {
    if (this.latencies.length === 0) {
      return 0;
    }
    return Math.max(...this.latencies);
  }

  /**
   * 获取丢帧数
   */
  getDroppedFrames(): number {
    return this.droppedFrames;
  }

  /**
   * 获取总帧数
   */
  getTotalFrames(): number {
    return this.totalFrames;
  }

  /**
   * 获取丢帧率（百分比）
   */
  getDropRate(): number {
    if (this.totalFrames === 0) {
      return 0;
    }
    return (this.droppedFrames / this.totalFrames) * 100;
  }

  /**
   * 获取完整统计信息
   */
  getStats(): PerformanceStats {
    return {
      fps: this.getFPS(),
      avgLatency: this.getAvgLatency(),
      p50Latency: this.getP50Latency(),
      p95Latency: this.getP95Latency(),
      p99Latency: this.getP99Latency(),
      minLatency: this.getMinLatency(),
      maxLatency: this.getMaxLatency(),
      frameCount: this.totalFrames,
      droppedFrames: this.droppedFrames,
    };
  }

  /**
   * 重置统计信息
   */
  reset(): void {
    this.frameTimestamps = [];
    this.latencies = [];
    this.droppedFrames = 0;
    this.totalFrames = 0;
    this.lastFrameTime = 0;
  }

  /**
   * 获取延迟历史记录（用于绘制图表）
   * @param maxPoints 最多返回多少个数据点
   */
  getLatencyHistory(maxPoints: number = 60): number[] {
    if (this.latencies.length <= maxPoints) {
      return [...this.latencies];
    }

    // 采样以减少数据点
    const step = this.latencies.length / maxPoints;
    const result: number[] = [];

    for (let i = 0; i < maxPoints; i++) {
      const index = Math.floor(i * step);
      result.push(this.latencies[index]);
    }

    return result;
  }

  /**
   * 获取 FPS 历史记录（用于绘制图表）
   * @param maxPoints 最多返回多少个数据点
   * @param windowSize 计算 FPS 的窗口大小（帧数）
   */
  getFPSHistory(maxPoints: number = 60, windowSize: number = 10): number[] {
    if (this.frameTimestamps.length < windowSize) {
      return [];
    }

    const result: number[] = [];
    const step = Math.max(
      1,
      Math.floor((this.frameTimestamps.length - windowSize) / maxPoints),
    );

    for (
      let i = windowSize;
      i < this.frameTimestamps.length;
      i += step
    ) {
      const startTime = this.frameTimestamps[i - windowSize];
      const endTime = this.frameTimestamps[i];
      const duration = endTime - startTime;

      if (duration > 0) {
        const fps = (windowSize / duration) * 1000;
        result.push(fps);
      }
    }

    return result;
  }

  /**
   * 导出统计数据为 JSON
   */
  exportJSON(): string {
    return JSON.stringify({
      stats: this.getStats(),
      latencyHistory: this.latencies,
      frameTimestamps: this.frameTimestamps,
    }, null, 2);
  }

  /**
   * 导出统计数据为 CSV
   */
  exportCSV(): string {
    const lines: string[] = [
      'Metric,Value',
      `FPS,${this.getFPS()}`,
      `Avg Latency (ms),${this.getAvgLatency()}`,
      `P50 Latency (ms),${this.getP50Latency()}`,
      `P95 Latency (ms),${this.getP95Latency()}`,
      `P99 Latency (ms),${this.getP99Latency()}`,
      `Min Latency (ms),${this.getMinLatency()}`,
      `Max Latency (ms),${this.getMaxLatency()}`,
      `Total Frames,${this.totalFrames}`,
      `Dropped Frames,${this.droppedFrames}`,
      `Drop Rate (%),${this.getDropRate()}`,
    ];

    return lines.join('\n');
  }

  /**
   * 生成性能报告
   */
  generateReport(): string {
    const stats = this.getStats();

    return `
Performance Report
==================
FPS: ${stats.fps.toFixed(2)}
Latency:
  - Average: ${stats.avgLatency.toFixed(2)} ms
  - P50: ${stats.p50Latency.toFixed(2)} ms
  - P95: ${stats.p95Latency.toFixed(2)} ms
  - P99: ${stats.p99Latency.toFixed(2)} ms
  - Min: ${stats.minLatency.toFixed(2)} ms
  - Max: ${stats.maxLatency.toFixed(2)} ms
Frames:
  - Total: ${stats.frameCount}
  - Dropped: ${stats.droppedFrames} (${this.getDropRate().toFixed(2)}%)
    `.trim();
  }
}
