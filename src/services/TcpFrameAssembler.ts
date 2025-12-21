/**
 * TCP Frame Assembler
 *
 * Assembles complete JPEG frames from TCP video chunks
 * Replaces VideoStreamReceiver for TCP-based video streaming
 */

import { VideoFrame } from '../types';
import type { ParsedPacket } from './FramePacketParser';

/**
 * Frame chunk information
 */
interface FrameChunks {
  chunks: Uint8Array[];
  totalChunks: number;
  receivedCount: number;
  timestamp: number;
}

/**
 * Video stream statistics
 */
export interface VideoStreamStats {
  droppedFrames: number;
  receivedFrames: number;
  avgLatency: number;
  currentFPS: number;
}

/**
 * TCP Frame Assembler
 * Receives TCP video chunks and reassembles them into complete JPEG frames
 */
export class TcpFrameAssembler {
  private chunkMap: Map<number, FrameChunks> = new Map();

  // Statistics
  private droppedFrames: number = 0;
  private receivedFrames: number = 0;
  private latencies: number[] = [];
  private frameTimestamps: number[] = [];

  // Configuration
  private readonly frameTimeout: number = 1000; // 1 second timeout
  private readonly maxCachedFrames: number = 5;

  // Callbacks
  private onFrameComplete: ((frame: VideoFrame) => void) | null = null;

  // Cleanup timer
  private cleanupInterval: NodeJS.Timeout | null = null;

  /**
   * Constructor
   */
  constructor() {
    // Start periodic cleanup
    this.startCleanupTimer();
  }

  /**
   * Set frame completion callback
   */
  setFrameCallback(callback: (frame: VideoFrame) => void): void {
    this.onFrameComplete = callback;
  }

  /**
   * Process a received packet
   * @param packet - Parsed packet from TcpVideoClient
   */
  onPacket(packet: ParsedPacket): void {
    const { header, data } = packet;
    const { frameId, chunkId, totalChunks } = header;

    // Get or create frame info
    let frameInfo = this.chunkMap.get(frameId);
    if (!frameInfo) {
      frameInfo = {
        chunks: new Array(totalChunks),
        totalChunks,
        receivedCount: 0,
        timestamp: Date.now(),
      };
      this.chunkMap.set(frameId, frameInfo);
    }

    // Check if chunk already exists (prevent duplicates)
    if (frameInfo.chunks[chunkId]) {
      return;
    }

    // Store chunk data (make a copy to avoid reference issues)
    frameInfo.chunks[chunkId] = new Uint8Array(data);
    frameInfo.receivedCount++;

    // Check if frame is complete
    if (frameInfo.receivedCount === frameInfo.totalChunks) {
      this.assembleFrame(frameId, frameInfo);
    }
  }

  /**
   * Assemble complete frame from chunks
   */
  private assembleFrame(frameId: number, frameInfo: FrameChunks): void {
    // Calculate total size
    let totalSize = 0;
    for (const chunk of frameInfo.chunks) {
      if (chunk) {
        totalSize += chunk.length;
      }
    }

    // Assemble data
    const completeData = new Uint8Array(totalSize);
    let offset = 0;
    for (const chunk of frameInfo.chunks) {
      if (chunk) {
        completeData.set(chunk, offset);
        offset += chunk.length;
      }
    }

    // Extract width and height from JPEG header if needed
    // For now, we'll use default values since JPEG contains this info
    const { width, height } = this.extractJpegDimensions(completeData);

    // Create complete frame object
    const frame: VideoFrame = {
      frameId,
      data: completeData,
      timestamp: frameInfo.timestamp,
      width,
      height,
    };

    // Update statistics
    const now = Date.now();
    const latency = now - frameInfo.timestamp;
    this.latencies.push(latency);
    this.frameTimestamps.push(now);
    this.receivedFrames++;

    // Limit statistics data size
    if (this.latencies.length > 60) {
      this.latencies.shift();
    }
    if (this.frameTimestamps.length > 60) {
      this.frameTimestamps.shift();
    }

    // Remove from map
    this.chunkMap.delete(frameId);

    // Trigger callback
    this.onFrameComplete?.(frame);
  }

  /**
   * Extract JPEG dimensions from JPEG data
   * This is a simplified parser that looks for SOF0 marker
   */
  private extractJpegDimensions(data: Uint8Array): { width: number; height: number } {
    // Default dimensions
    let width = 640;
    let height = 480;

    try {
      // Look for SOF0 marker (0xFFC0)
      for (let i = 0; i < data.length - 9; i++) {
        if (data[i] === 0xFF && data[i + 1] === 0xC0) {
          // SOF0 marker found
          // Height is at offset +5,+6 (big-endian)
          // Width is at offset +7,+8 (big-endian)
          height = (data[i + 5] << 8) | data[i + 6];
          width = (data[i + 7] << 8) | data[i + 8];
          break;
        }
      }
    } catch (error) {
      console.warn('[TcpFrameAssembler] Failed to extract JPEG dimensions:', error);
    }

    return { width, height };
  }

  /**
   * Clean up timed-out frames
   */
  private cleanup(): void {
    const now = Date.now();
    const toDelete: number[] = [];

    this.chunkMap.forEach((frameInfo, frameId) => {
      if (now - frameInfo.timestamp > this.frameTimeout) {
        toDelete.push(frameId);
        this.droppedFrames++;
      }
    });

    toDelete.forEach(frameId => this.chunkMap.delete(frameId));

    // Limit cached frame count
    if (this.chunkMap.size > this.maxCachedFrames) {
      const sortedFrames = Array.from(this.chunkMap.entries()).sort(
        (a, b) => a[1].timestamp - b[1].timestamp
      );

      // Remove oldest frames
      const toRemove = sortedFrames.slice(0, this.chunkMap.size - this.maxCachedFrames);
      toRemove.forEach(([frameId]) => {
        this.chunkMap.delete(frameId);
        this.droppedFrames++;
      });
    }
  }

  /**
   * Start cleanup timer
   */
  private startCleanupTimer(): void {
    this.cleanupInterval = setInterval(() => {
      this.cleanup();
    }, 500); // Clean up every 500ms
  }

  /**
   * Get statistics
   */
  getStats(): VideoStreamStats {
    // Calculate FPS
    let currentFPS = 0;
    if (this.frameTimestamps.length >= 2) {
      const duration =
        this.frameTimestamps[this.frameTimestamps.length - 1] - this.frameTimestamps[0];
      currentFPS = ((this.frameTimestamps.length - 1) / duration) * 1000;
    }

    // Calculate average latency
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
   * Reset statistics
   */
  resetStats(): void {
    this.droppedFrames = 0;
    this.receivedFrames = 0;
    this.latencies = [];
    this.frameTimestamps = [];
  }

  /**
   * Destroy assembler
   */
  destroy(): void {
    if (this.cleanupInterval) {
      clearInterval(this.cleanupInterval);
      this.cleanupInterval = null;
    }

    this.chunkMap.clear();
    this.onFrameComplete = null;
  }
}

// Singleton instance
let assemblerInstance: TcpFrameAssembler | null = null;

/**
 * Get the singleton instance of TcpFrameAssembler
 */
export function getTcpFrameAssembler(): TcpFrameAssembler {
  if (!assemblerInstance) {
    assemblerInstance = new TcpFrameAssembler();
  }
  return assemblerInstance;
}
