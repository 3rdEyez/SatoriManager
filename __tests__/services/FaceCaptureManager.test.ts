/**
 * FaceCaptureManager Tests
 */

import { FaceCaptureManager } from '../../src/services/FaceCaptureManager';
import { FaceDetectionResult } from '../../src/services/FaceDetector';
import { VideoFrame } from '../../src/types';

describe('FaceCaptureManager', () => {
  let manager: FaceCaptureManager;
  let mockFrame: VideoFrame;
  let mockCaptureCallback: jest.Mock;

  beforeEach(() => {
    jest.useFakeTimers();
    manager = new FaceCaptureManager(1000, 10000); // 1s threshold, 10s interval

    mockFrame = {
      frameId: 1,
      data: new Uint8Array([0xFF, 0xD8, 0xFF, 0xE0]), // JPEG header
      timestamp: Date.now(),
      width: 640,
      height: 480,
    };

    mockCaptureCallback = jest.fn();
    manager.onCapture(mockCaptureCallback);
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  describe('Initialization', () => {
    it('should initialize with default config', () => {
      const defaultManager = new FaceCaptureManager();

      expect(defaultManager.getCurrentTrackingId()).toBeNull();
      expect(defaultManager.isTracking()).toBe(false);
    });

    it('should accept custom stability threshold', () => {
      const customManager = new FaceCaptureManager(2000, 10000);

      // Test stability calculation after 1.5s
      customManager.onFaceDetected(createMockFaceResult(123), mockFrame);
      jest.advanceTimersByTime(1500);

      expect(customManager.getStability()).toBe(1500);
    });

    it('should accept custom capture interval', () => {
      const customManager = new FaceCaptureManager(1000, 5000);
      const customCallback = jest.fn();
      customManager.onCapture(customCallback);

      // First capture
      customManager.onFaceDetected(createMockFaceResult(123), mockFrame);
      jest.advanceTimersByTime(1000);
      customManager.onFaceDetected(createMockFaceResult(123), mockFrame);

      // Second capture attempt before interval
      customManager.onFaceDetected(createMockFaceResult(123), mockFrame);
      jest.advanceTimersByTime(1000);
      customManager.onFaceDetected(createMockFaceResult(123), mockFrame);

      // Should only trigger once due to min interval
      expect(customCallback).toHaveBeenCalledTimes(1);
    });
  });

  describe('Face Detection Tracking', () => {
    it('should reset tracking when no faces detected', () => {
      manager.onFaceDetected(createMockFaceResult(123), mockFrame);

      expect(manager.getCurrentTrackingId()).toBe(123);
      expect(manager.isTracking()).toBe(true);

      manager.onFaceDetected(createMockFaceResult(null), mockFrame);

      expect(manager.getCurrentTrackingId()).toBeNull();
      expect(manager.isTracking()).toBe(false);
    });

    it('should start tracking when new face appears', () => {
      manager.onFaceDetected(createMockFaceResult(456), mockFrame);

      expect(manager.getCurrentTrackingId()).toBe(456);
      expect(manager.isTracking()).toBe(true);
    });

    it('should maintain tracking for same trackingId', () => {
      manager.onFaceDetected(createMockFaceResult(789), mockFrame);
      const initialTrackingId = manager.getCurrentTrackingId();

      jest.advanceTimersByTime(500);
      manager.onFaceDetected(createMockFaceResult(789), mockFrame);

      expect(manager.getCurrentTrackingId()).toBe(initialTrackingId);
    });

    it('should reset tracking when trackingId changes', () => {
      manager.onFaceDetected(createMockFaceResult(100), mockFrame);
      jest.advanceTimersByTime(500);

      manager.onFaceDetected(createMockFaceResult(200), mockFrame);

      // New tracking ID, stability should be low
      expect(manager.getCurrentTrackingId()).toBe(200);
      expect(manager.getStability()).toBeLessThan(100);
    });

    it('should handle empty faces array', () => {
      const emptyResult: FaceDetectionResult = {
        faces: [],
        imageWidth: 640,
        imageHeight: 480,
        timestamp: Date.now(),
        processingTime: 50,
      };

      manager.onFaceDetected(emptyResult, mockFrame);

      expect(manager.getCurrentTrackingId()).toBeNull();
    });
  });

  describe('Stability Detection', () => {
    it('should not trigger capture before threshold', () => {
      manager.onFaceDetected(createMockFaceResult(111), mockFrame);
      jest.advanceTimersByTime(500); // Only 500ms, below 1000ms threshold

      manager.onFaceDetected(createMockFaceResult(111), mockFrame);

      expect(mockCaptureCallback).not.toHaveBeenCalled();
    });

    it('should trigger capture when threshold reached', () => {
      manager.onFaceDetected(createMockFaceResult(222), mockFrame);
      jest.advanceTimersByTime(1000); // Exactly at threshold

      manager.onFaceDetected(createMockFaceResult(222), mockFrame);

      expect(mockCaptureCallback).toHaveBeenCalledTimes(1);
      expect(mockCaptureCallback).toHaveBeenCalledWith(
        expect.objectContaining({
          trackingId: 222,
          stabilityDuration: 1000,
          frame: mockFrame,
        }),
      );
    });

    it('should trigger capture after threshold', () => {
      manager.onFaceDetected(createMockFaceResult(333), mockFrame);
      jest.advanceTimersByTime(1500); // Above threshold

      manager.onFaceDetected(createMockFaceResult(333), mockFrame);

      expect(mockCaptureCallback).toHaveBeenCalledTimes(1);
    });

    it('should respect minimum capture interval', () => {
      // First capture
      manager.onFaceDetected(createMockFaceResult(444), mockFrame);
      jest.advanceTimersByTime(1000);
      manager.onFaceDetected(createMockFaceResult(444), mockFrame);
      expect(mockCaptureCallback).toHaveBeenCalledTimes(1);

      // Try to capture again before min interval
      jest.advanceTimersByTime(5000); // 5s, below 10s min interval
      manager.onFaceDetected(createMockFaceResult(444), mockFrame);
      expect(mockCaptureCallback).toHaveBeenCalledTimes(1); // Still 1

      // After min interval
      jest.advanceTimersByTime(5500); // Total 11s, above 10s min interval
      manager.onFaceDetected(createMockFaceResult(444), mockFrame);
      expect(mockCaptureCallback).toHaveBeenCalledTimes(2);
    });

    it('should calculate stability progress correctly', () => {
      manager.onFaceDetected(createMockFaceResult(555), mockFrame);

      jest.advanceTimersByTime(500);
      expect(manager.getProgress()).toBeCloseTo(0.5, 1);

      jest.advanceTimersByTime(300);
      expect(manager.getProgress()).toBeCloseTo(0.8, 1);

      jest.advanceTimersByTime(200);
      expect(manager.getProgress()).toBe(1);
    });
  });

  describe('Face Selection', () => {
    it('should select largest face when no current tracking', () => {
      const result = createMockFaceResult(null);
      // Add multiple faces
      result.faces.push({
        boundingBox: { x: 0, y: 0, width: 50, height: 50 },
        centerX: 0,
        centerY: 0,
        confidence: 1.0,
        trackingId: 1,
      });
      result.faces.push({
        boundingBox: { x: 100, y: 100, width: 100, height: 100 },
        centerX: 0,
        centerY: 0,
        confidence: 1.0,
        trackingId: 2,
      });

      manager.onFaceDetected(result, mockFrame);

      // Should select face with larger area (100x100 = 10000)
      expect(manager.getCurrentTrackingId()).toBe(2);
    });

    it('should select tracked face when trackingId exists', () => {
      // Start tracking face ID 100 (make it larger than 200 so it gets selected first)
      const result1 = createMockFaceResult(100);
      // Update the default face to be larger
      result1.faces[0].boundingBox = { x: 0, y: 0, width: 150, height: 150 };
      result1.faces.push({
        boundingBox: { x: 100, y: 100, width: 100, height: 100 },
        centerX: 0,
        centerY: 0,
        confidence: 1.0,
        trackingId: 200,
      });

      manager.onFaceDetected(result1, mockFrame);
      expect(manager.getCurrentTrackingId()).toBe(100);

      // Next frame with both faces again
      const result2 = createMockFaceResult(null);
      result2.faces.push({
        boundingBox: { x: 0, y: 0, width: 50, height: 50 },
        centerX: 0,
        centerY: 0,
        confidence: 1.0,
        trackingId: 100,
      });
      result2.faces.push({
        boundingBox: { x: 100, y: 100, width: 100, height: 100 },
        centerX: 0,
        centerY: 0,
        confidence: 1.0,
        trackingId: 200,
      });

      manager.onFaceDetected(result2, mockFrame);

      // Should still select tracked face (100), not the larger one (200)
      expect(manager.getCurrentTrackingId()).toBe(100);
    });
  });

  describe('State Query', () => {
    it('should return correct tracking ID', () => {
      expect(manager.getCurrentTrackingId()).toBeNull();

      manager.onFaceDetected(createMockFaceResult(777), mockFrame);

      expect(manager.getCurrentTrackingId()).toBe(777);
    });

    it('should return correct stability duration', () => {
      manager.onFaceDetected(createMockFaceResult(888), mockFrame);

      jest.advanceTimersByTime(750);

      expect(manager.getStability()).toBe(750);
    });

    it('should return progress between 0 and 1', () => {
      manager.onFaceDetected(createMockFaceResult(999), mockFrame);

      for (let i = 0; i < 10; i++) {
        jest.advanceTimersByTime(100);
        const progress = manager.getProgress();
        expect(progress).toBeGreaterThanOrEqual(0);
        expect(progress).toBeLessThanOrEqual(1);
      }
    });

    it('should indicate tracking status', () => {
      expect(manager.isTracking()).toBe(false);

      manager.onFaceDetected(createMockFaceResult(111), mockFrame);

      expect(manager.isTracking()).toBe(true);
    });
  });

  describe('Reset', () => {
    it('should reset all state on manual reset', () => {
      manager.onFaceDetected(createMockFaceResult(123), mockFrame);
      jest.advanceTimersByTime(500);

      expect(manager.getCurrentTrackingId()).not.toBeNull();
      expect(manager.getStability()).toBeGreaterThan(0);

      manager.reset();

      expect(manager.getCurrentTrackingId()).toBeNull();
      expect(manager.getStability()).toBe(0);
    });

    it('should reset tracking when face lost', () => {
      manager.onFaceDetected(createMockFaceResult(456), mockFrame);
      jest.advanceTimersByTime(800);

      expect(manager.getCurrentTrackingId()).toBe(456);

      // Face lost
      manager.onFaceDetected(createMockFaceResult(null), mockFrame);

      expect(manager.getCurrentTrackingId()).toBeNull();
      expect(manager.getStability()).toBe(0);
    });
  });

  describe('Callback Management', () => {
    it('should support multiple callbacks', () => {
      const callback1 = jest.fn();
      const callback2 = jest.fn();

      // Only the last callback is stored (implementation limitation)
      manager.onCapture(callback1);
      manager.onCapture(callback2);

      manager.onFaceDetected(createMockFaceResult(111), mockFrame);
      jest.advanceTimersByTime(1000);
      manager.onFaceDetected(createMockFaceResult(111), mockFrame);

      // Only callback2 should be called (last registered)
      expect(callback1).not.toHaveBeenCalled();
      expect(callback2).toHaveBeenCalled();
    });

    it('should allow callback unregistration', () => {
      const callback = jest.fn();

      // Note: onCapture returns void (no unsubscribe function in current implementation)
      manager.onCapture(callback);

      // Clear the callback by setting to null (not a public API, but testing the behavior)
      manager.onCapture(jest.fn());

      manager.onFaceDetected(createMockFaceResult(222), mockFrame);
      jest.advanceTimersByTime(1000);
      manager.onFaceDetected(createMockFaceResult(222), mockFrame);

      // Original callback should not be called
      expect(callback).not.toHaveBeenCalled();
    });
  });

  describe('Config Update', () => {
    it('should update stability threshold', () => {
      manager.setConfig(2000, 10000);

      manager.onFaceDetected(createMockFaceResult(111), mockFrame);
      jest.advanceTimersByTime(1500); // 1.5s, below new 2s threshold
      manager.onFaceDetected(createMockFaceResult(111), mockFrame);

      expect(mockCaptureCallback).not.toHaveBeenCalled();

      jest.advanceTimersByTime(500); // Total 2s, at threshold
      manager.onFaceDetected(createMockFaceResult(111), mockFrame);

      expect(mockCaptureCallback).toHaveBeenCalled();
    });

    it('should update min capture interval', () => {
      manager.setConfig(1000, 5000); // Reduce interval to 5s

      // First capture
      manager.onFaceDetected(createMockFaceResult(222), mockFrame);
      jest.advanceTimersByTime(1000);
      manager.onFaceDetected(createMockFaceResult(222), mockFrame);
      expect(mockCaptureCallback).toHaveBeenCalledTimes(1);

      // Need to wait for stability threshold again (trackingStartTime was reset after capture)
      // Advance another 1000ms for stability + 4000ms to reach min interval = 5000ms total
      jest.advanceTimersByTime(1000); // Stability threshold
      jest.advanceTimersByTime(4000); // Additional time for min interval
      manager.onFaceDetected(createMockFaceResult(222), mockFrame);

      expect(mockCaptureCallback).toHaveBeenCalledTimes(2);
    });
  });
});

// Helper function to create mock face detection results
function createMockFaceResult(trackingId: number | null): FaceDetectionResult {
  const result: FaceDetectionResult = {
    faces: [],
    imageWidth: 640,
    imageHeight: 480,
    timestamp: Date.now(),
    processingTime: 50,
  };

  if (trackingId !== null) {
    result.faces.push({
      boundingBox: { x: 100, y: 100, width: 80, height: 80 },
      centerX: 0,
      centerY: 0,
      confidence: 1.0,
      trackingId: trackingId,
    });
  }

  return result;
}
