/**
 * TcpFrameAssembler Tests
 */

import { TcpFrameAssembler } from '../../src/services/TcpFrameAssembler';
import { VideoFrame } from '../../src/types';
import type { ParsedPacket } from '../../src/services/FramePacketParser';

describe('TcpFrameAssembler', () => {
  let assembler: TcpFrameAssembler;
  let frameCallback: jest.Mock;

  beforeEach(() => {
    assembler = new TcpFrameAssembler();
    frameCallback = jest.fn();
    assembler.setFrameCallback(frameCallback);
  });

  afterEach(() => {
    assembler.destroy();
  });

  const createPacket = (
    frameId: number,
    chunkId: number,
    totalChunks: number,
    data: Uint8Array
  ): ParsedPacket => ({
    header: {
      magic: 0xFFD8,
      frameId,
      totalChunks,
      chunkId,
      chunkSize: data.length,
    },
    data,
  });

  const createJpegData = (size: number): Uint8Array => {
    // Create minimal JPEG with SOF0 marker for dimension extraction
    const data = new Uint8Array(size);
    data[0] = 0xFF;
    data[1] = 0xD8; // JPEG start marker
    // Add SOF0 marker at offset 10
    if (size > 20) {
      data[10] = 0xFF;
      data[11] = 0xC0; // SOF0 marker
      data[12] = 0x00;
      data[13] = 0x11; // Length
      data[14] = 0x08; // Precision
      data[15] = 0x01; // Height high byte
      data[16] = 0xE0; // Height low byte (480)
      data[17] = 0x02; // Width high byte
      data[18] = 0x80; // Width low byte (640)
    }
    return data;
  };

  describe('single chunk frame', () => {
    it('should assemble frame from single chunk', () => {
      const data = createJpegData(100);
      const packet = createPacket(1, 0, 1, data);

      assembler.onPacket(packet);

      expect(frameCallback).toHaveBeenCalledTimes(1);
      const frame: VideoFrame = frameCallback.mock.calls[0][0];
      expect(frame.frameId).toBe(1);
      expect(frame.data).toEqual(data);
    });

    it('should extract JPEG dimensions', () => {
      const data = createJpegData(100);
      const packet = createPacket(1, 0, 1, data);

      assembler.onPacket(packet);

      const frame: VideoFrame = frameCallback.mock.calls[0][0];
      expect(frame.width).toBe(640);
      expect(frame.height).toBe(480);
    });
  });

  describe('multi-chunk frame', () => {
    it('should assemble frame from multiple chunks in order', () => {
      const chunk1 = new Uint8Array([0xFF, 0xD8, 0x01, 0x02]);
      const chunk2 = new Uint8Array([0x03, 0x04, 0x05, 0x06]);
      const chunk3 = new Uint8Array([0x07, 0x08, 0x09, 0x0A]);

      assembler.onPacket(createPacket(1, 0, 3, chunk1));
      expect(frameCallback).not.toHaveBeenCalled();

      assembler.onPacket(createPacket(1, 1, 3, chunk2));
      expect(frameCallback).not.toHaveBeenCalled();

      assembler.onPacket(createPacket(1, 2, 3, chunk3));
      expect(frameCallback).toHaveBeenCalledTimes(1);

      const frame: VideoFrame = frameCallback.mock.calls[0][0];
      expect(frame.frameId).toBe(1);
      expect(frame.data).toEqual(
        new Uint8Array([0xFF, 0xD8, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A])
      );
    });

    it('should assemble frame from chunks received out of order', () => {
      const chunk1 = new Uint8Array([0xFF, 0xD8, 0x01, 0x02]);
      const chunk2 = new Uint8Array([0x03, 0x04, 0x05, 0x06]);
      const chunk3 = new Uint8Array([0x07, 0x08, 0x09, 0x0A]);

      // Receive chunks out of order: 2, 0, 1
      assembler.onPacket(createPacket(1, 2, 3, chunk3));
      expect(frameCallback).not.toHaveBeenCalled();

      assembler.onPacket(createPacket(1, 0, 3, chunk1));
      expect(frameCallback).not.toHaveBeenCalled();

      assembler.onPacket(createPacket(1, 1, 3, chunk2));
      expect(frameCallback).toHaveBeenCalledTimes(1);

      const frame: VideoFrame = frameCallback.mock.calls[0][0];
      expect(frame.data).toEqual(
        new Uint8Array([0xFF, 0xD8, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A])
      );
    });

    it('should handle duplicate chunks', () => {
      const chunk1 = new Uint8Array([0xFF, 0xD8, 0x01, 0x02]);
      const chunk2 = new Uint8Array([0x03, 0x04, 0x05, 0x06]);

      assembler.onPacket(createPacket(1, 0, 2, chunk1));
      assembler.onPacket(createPacket(1, 0, 2, chunk1)); // Duplicate
      assembler.onPacket(createPacket(1, 1, 2, chunk2));

      expect(frameCallback).toHaveBeenCalledTimes(1);
    });
  });

  describe('multiple frames', () => {
    it('should handle multiple frames independently', () => {
      const frame1Data = createJpegData(50);
      const frame2Data = createJpegData(60);

      assembler.onPacket(createPacket(1, 0, 1, frame1Data));
      assembler.onPacket(createPacket(2, 0, 1, frame2Data));

      expect(frameCallback).toHaveBeenCalledTimes(2);
      expect(frameCallback.mock.calls[0][0].frameId).toBe(1);
      expect(frameCallback.mock.calls[1][0].frameId).toBe(2);
    });

    it('should handle interleaved chunks from different frames', () => {
      const frame1chunk1 = new Uint8Array([0xFF, 0xD8, 0x01]);
      const frame1chunk2 = new Uint8Array([0x02, 0x03]);
      const frame2chunk1 = new Uint8Array([0xFF, 0xD8, 0x04]);
      const frame2chunk2 = new Uint8Array([0x05, 0x06]);

      assembler.onPacket(createPacket(1, 0, 2, frame1chunk1));
      assembler.onPacket(createPacket(2, 0, 2, frame2chunk1));
      assembler.onPacket(createPacket(1, 1, 2, frame1chunk2));
      assembler.onPacket(createPacket(2, 1, 2, frame2chunk2));

      expect(frameCallback).toHaveBeenCalledTimes(2);
    });
  });

  describe('statistics', () => {
    it('should track received frames', () => {
      const data = createJpegData(100);

      assembler.onPacket(createPacket(1, 0, 1, data));
      assembler.onPacket(createPacket(2, 0, 1, data));
      assembler.onPacket(createPacket(3, 0, 1, data));

      const stats = assembler.getStats();
      expect(stats.receivedFrames).toBe(3);
    });

    it('should calculate FPS', (done) => {
      jest.useFakeTimers();

      const data = createJpegData(100);

      // Send 10 frames over 1 second
      for (let i = 0; i < 10; i++) {
        assembler.onPacket(createPacket(i, 0, 1, data));
        jest.advanceTimersByTime(100);
      }

      const stats = assembler.getStats();
      expect(stats.currentFPS).toBeGreaterThan(0);
      expect(stats.currentFPS).toBeLessThanOrEqual(10);

      jest.useRealTimers();
      done();
    });

    it('should calculate average latency', () => {
      const data = createJpegData(100);

      assembler.onPacket(createPacket(1, 0, 1, data));
      assembler.onPacket(createPacket(2, 0, 1, data));

      const stats = assembler.getStats();
      expect(stats.avgLatency).toBeGreaterThanOrEqual(0);
    });

    it('should reset statistics', () => {
      const data = createJpegData(100);

      assembler.onPacket(createPacket(1, 0, 1, data));
      assembler.onPacket(createPacket(2, 0, 1, data));

      assembler.resetStats();

      const stats = assembler.getStats();
      expect(stats.receivedFrames).toBe(0);
      expect(stats.droppedFrames).toBe(0);
    });
  });

  describe('frame timeout', () => {
    it('should drop incomplete frames after timeout', (done) => {
      const chunk1 = new Uint8Array([0xFF, 0xD8, 0x01]);

      // Send only first chunk of 2-chunk frame
      assembler.onPacket(createPacket(1, 0, 2, chunk1));

      // Wait for timeout and cleanup
      setTimeout(() => {
        const stats = assembler.getStats();
        expect(stats.droppedFrames).toBeGreaterThanOrEqual(1);
        expect(frameCallback).not.toHaveBeenCalled();
        done();
      }, 1600);
    });

    it('should not drop frames that complete before timeout', (done) => {
      const chunk1 = new Uint8Array([0xFF, 0xD8, 0x01]);
      const chunk2 = new Uint8Array([0x02, 0x03]);

      assembler.onPacket(createPacket(1, 0, 2, chunk1));

      // Complete frame before timeout
      setTimeout(() => {
        assembler.onPacket(createPacket(1, 1, 2, chunk2));

        const stats = assembler.getStats();
        expect(stats.droppedFrames).toBe(0);
        expect(frameCallback).toHaveBeenCalledTimes(1);
        done();
      }, 500);
    });
  });

  describe('max cached frames', () => {
    it('should drop oldest incomplete frames when cache is full', (done) => {
      const chunk = new Uint8Array([0xFF, 0xD8]);

      // Send first chunk of 6 different frames (max is 5)
      for (let i = 0; i < 6; i++) {
        assembler.onPacket(createPacket(i, 0, 2, chunk));
      }

      // Wait for cleanup to run
      setTimeout(() => {
        const stats = assembler.getStats();
        expect(stats.droppedFrames).toBeGreaterThanOrEqual(1);
        done();
      }, 600);
    });
  });

  describe('destroy', () => {
    it('should clean up resources', () => {
      const data = createJpegData(100);
      assembler.onPacket(createPacket(1, 0, 2, data));

      assembler.destroy();

      // Should not crash when receiving packets after destroy
      assembler.onPacket(createPacket(1, 1, 2, data));
    });

    it('should clear callback', () => {
      assembler.destroy();

      const data = createJpegData(100);
      assembler.onPacket(createPacket(1, 0, 1, data));

      expect(frameCallback).not.toHaveBeenCalled();
    });
  });
});
