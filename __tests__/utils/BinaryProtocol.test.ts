/**
 * BinaryProtocol Utilities Tests
 */

import {
  readUint16LE,
  readUint32LE,
  validateMagicNumber,
  parsePacketHeader,
  getPacketHeaderSize,
  getJpegMagicNumber,
} from '../../src/utils/BinaryProtocol';

describe('BinaryProtocol', () => {
  describe('readUint16LE', () => {
    it('should read 16-bit little-endian value correctly', () => {
      const buffer = new Uint8Array([0xD8, 0xFF, 0x00, 0x00]);
      expect(readUint16LE(buffer, 0)).toBe(0xFFD8);
    });

    it('should read from specified offset', () => {
      const buffer = new Uint8Array([0x00, 0x00, 0x34, 0x12]);
      expect(readUint16LE(buffer, 2)).toBe(0x1234);
    });

    it('should handle zero value', () => {
      const buffer = new Uint8Array([0x00, 0x00]);
      expect(readUint16LE(buffer, 0)).toBe(0);
    });

    it('should handle max value', () => {
      const buffer = new Uint8Array([0xFF, 0xFF]);
      expect(readUint16LE(buffer, 0)).toBe(0xFFFF);
    });
  });

  describe('readUint32LE', () => {
    it('should read 32-bit little-endian value correctly', () => {
      const buffer = new Uint8Array([0x78, 0x56, 0x34, 0x12]);
      expect(readUint32LE(buffer, 0)).toBe(0x12345678);
    });

    it('should read from specified offset', () => {
      const buffer = new Uint8Array([0x00, 0x00, 0x04, 0x03, 0x02, 0x01]);
      expect(readUint32LE(buffer, 2)).toBe(0x01020304);
    });

    it('should handle zero value', () => {
      const buffer = new Uint8Array([0x00, 0x00, 0x00, 0x00]);
      expect(readUint32LE(buffer, 0)).toBe(0);
    });

    it('should handle max value as unsigned', () => {
      const buffer = new Uint8Array([0xFF, 0xFF, 0xFF, 0xFF]);
      expect(readUint32LE(buffer, 0)).toBe(0xFFFFFFFF);
    });
  });

  describe('validateMagicNumber', () => {
    it('should validate correct JPEG magic number', () => {
      const buffer = new Uint8Array([0xD8, 0xFF]);
      expect(validateMagicNumber(buffer)).toBe(true);
    });

    it('should reject incorrect magic number', () => {
      const buffer = new Uint8Array([0xFF, 0xD8]);
      expect(validateMagicNumber(buffer)).toBe(false);
    });

    it('should reject buffer too small', () => {
      const buffer = new Uint8Array([0xD8]);
      expect(validateMagicNumber(buffer)).toBe(false);
    });

    it('should reject empty buffer', () => {
      const buffer = new Uint8Array([]);
      expect(validateMagicNumber(buffer)).toBe(false);
    });
  });

  describe('parsePacketHeader', () => {
    it('should parse valid packet header', () => {
      // Magic: 0xFFD8, FrameID: 1, TotalChunks: 5, ChunkID: 0, ChunkSize: 1024
      const buffer = new Uint8Array([
        0xD8, 0xFF, // Magic (little-endian)
        0x01, 0x00, 0x00, 0x00, // Frame ID (little-endian)
        0x05, 0x00, // Total Chunks (little-endian)
        0x00, 0x00, // Chunk ID (little-endian)
        0x00, 0x04, // Chunk Size: 1024 (little-endian)
      ]);

      const header = parsePacketHeader(buffer);
      expect(header).not.toBeNull();
      expect(header?.magic).toBe(0xFFD8);
      expect(header?.frameId).toBe(1);
      expect(header?.totalChunks).toBe(5);
      expect(header?.chunkId).toBe(0);
      expect(header?.chunkSize).toBe(1024);
    });

    it('should reject buffer too small', () => {
      const buffer = new Uint8Array([0xD8, 0xFF, 0x01]);
      expect(parsePacketHeader(buffer)).toBeNull();
    });

    it('should reject invalid magic number', () => {
      const buffer = new Uint8Array([
        0xFF, 0xD8, // Wrong byte order
        0x01, 0x00, 0x00, 0x00,
        0x05, 0x00,
        0x00, 0x00,
        0x00, 0x04,
      ]);
      expect(parsePacketHeader(buffer)).toBeNull();
    });

    it('should reject zero total chunks', () => {
      const buffer = new Uint8Array([
        0xD8, 0xFF,
        0x01, 0x00, 0x00, 0x00,
        0x00, 0x00, // Total chunks = 0
        0x00, 0x00,
        0x00, 0x04,
      ]);
      expect(parsePacketHeader(buffer)).toBeNull();
    });

    it('should reject chunk ID >= total chunks', () => {
      const buffer = new Uint8Array([
        0xD8, 0xFF,
        0x01, 0x00, 0x00, 0x00,
        0x05, 0x00, // Total chunks = 5
        0x05, 0x00, // Chunk ID = 5 (should be < 5)
        0x00, 0x04,
      ]);
      expect(parsePacketHeader(buffer)).toBeNull();
    });

    it('should reject zero chunk size', () => {
      const buffer = new Uint8Array([
        0xD8, 0xFF,
        0x01, 0x00, 0x00, 0x00,
        0x05, 0x00,
        0x00, 0x00,
        0x00, 0x00, // Chunk size = 0
      ]);
      expect(parsePacketHeader(buffer)).toBeNull();
    });

    it('should parse header with large frame ID', () => {
      const buffer = new Uint8Array([
        0xD8, 0xFF,
        0xFF, 0xFF, 0xFF, 0xFF, // Max frame ID
        0x01, 0x00,
        0x00, 0x00,
        0x01, 0x00,
      ]);
      const header = parsePacketHeader(buffer);
      expect(header?.frameId).toBe(0xFFFFFFFF);
    });
  });

  describe('getPacketHeaderSize', () => {
    it('should return correct header size', () => {
      expect(getPacketHeaderSize()).toBe(12);
    });
  });

  describe('getJpegMagicNumber', () => {
    it('should return correct JPEG magic number', () => {
      expect(getJpegMagicNumber()).toBe(0xFFD8);
    });
  });
});
