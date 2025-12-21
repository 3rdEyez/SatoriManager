/**
 * FramePacketParser Tests
 */

import { FramePacketParser } from '../../src/services/FramePacketParser';

describe('FramePacketParser', () => {
  let parser: FramePacketParser;

  beforeEach(() => {
    parser = new FramePacketParser();
  });

  describe('parseHeader', () => {
    it('should parse valid header', () => {
      const buffer = new Uint8Array([
        0xD8, 0xFF, // Magic
        0x01, 0x00, 0x00, 0x00, // Frame ID: 1
        0x03, 0x00, // Total chunks: 3
        0x00, 0x00, // Chunk ID: 0
        0x00, 0x04, // Chunk size: 1024
      ]);

      const header = parser.parseHeader(buffer);
      expect(header).not.toBeNull();
      expect(header?.magic).toBe(0xFFD8);
      expect(header?.frameId).toBe(1);
      expect(header?.totalChunks).toBe(3);
      expect(header?.chunkId).toBe(0);
      expect(header?.chunkSize).toBe(1024);
    });

    it('should return null for invalid header', () => {
      const buffer = new Uint8Array([0xFF, 0xD8]); // Wrong byte order
      expect(parser.parseHeader(buffer)).toBeNull();
    });

    it('should return null for buffer too small', () => {
      const buffer = new Uint8Array([0xD8, 0xFF, 0x01]);
      expect(parser.parseHeader(buffer)).toBeNull();
    });
  });

  describe('parsePacket', () => {
    it('should parse complete packet with data', () => {
      const data = new Uint8Array([0xAA, 0xBB, 0xCC, 0xDD]);
      const buffer = new Uint8Array([
        0xD8, 0xFF, // Magic
        0x01, 0x00, 0x00, 0x00, // Frame ID: 1
        0x02, 0x00, // Total chunks: 2
        0x00, 0x00, // Chunk ID: 0
        0x04, 0x00, // Chunk size: 4
        ...data, // Data
      ]);

      const packet = parser.parsePacket(buffer);
      expect(packet).not.toBeNull();
      expect(packet?.header.frameId).toBe(1);
      expect(packet?.header.totalChunks).toBe(2);
      expect(packet?.header.chunkId).toBe(0);
      expect(packet?.header.chunkSize).toBe(4);
      expect(packet?.data).toEqual(data);
    });

    it('should return null for incomplete packet', () => {
      const buffer = new Uint8Array([
        0xD8, 0xFF,
        0x01, 0x00, 0x00, 0x00,
        0x02, 0x00,
        0x00, 0x00,
        0x10, 0x00, // Chunk size: 16
        0xAA, 0xBB, // Only 2 bytes of data (need 16)
      ]);

      expect(parser.parsePacket(buffer)).toBeNull();
    });

    it('should return null for invalid header', () => {
      const buffer = new Uint8Array([
        0xFF, 0xD8, // Wrong magic byte order
        0x01, 0x00, 0x00, 0x00,
        0x02, 0x00,
        0x00, 0x00,
        0x04, 0x00,
        0xAA, 0xBB, 0xCC, 0xDD,
      ]);

      expect(parser.parsePacket(buffer)).toBeNull();
    });

    it('should handle packet with large data', () => {
      const dataSize = 2048;
      const data = new Uint8Array(dataSize).fill(0x42);
      const buffer = new Uint8Array([
        0xD8, 0xFF,
        0x05, 0x00, 0x00, 0x00, // Frame ID: 5
        0x01, 0x00, // Total chunks: 1
        0x00, 0x00, // Chunk ID: 0
        0x00, 0x08, // Chunk size: 2048 (little-endian)
        ...data,
      ]);

      const packet = parser.parsePacket(buffer);
      expect(packet).not.toBeNull();
      expect(packet?.data.length).toBe(dataSize);
      expect(packet?.data[0]).toBe(0x42);
    });
  });

  describe('getExpectedPacketSize', () => {
    it('should calculate correct packet size', () => {
      const header = {
        magic: 0xFFD8,
        frameId: 1,
        totalChunks: 3,
        chunkId: 0,
        chunkSize: 1024,
      };

      expect(parser.getExpectedPacketSize(header)).toBe(12 + 1024);
    });

    it('should handle zero chunk size', () => {
      const header = {
        magic: 0xFFD8,
        frameId: 1,
        totalChunks: 1,
        chunkId: 0,
        chunkSize: 0,
      };

      expect(parser.getExpectedPacketSize(header)).toBe(12);
    });
  });

  describe('validatePacket', () => {
    it('should validate correct packet', () => {
      const packet = {
        header: {
          magic: 0xFFD8,
          frameId: 1,
          totalChunks: 3,
          chunkId: 1,
          chunkSize: 4,
        },
        data: new Uint8Array([0xAA, 0xBB, 0xCC, 0xDD]),
      };

      expect(parser.validatePacket(packet)).toBe(true);
    });

    it('should reject packet with chunk ID >= total chunks', () => {
      const packet = {
        header: {
          magic: 0xFFD8,
          frameId: 1,
          totalChunks: 3,
          chunkId: 3, // Invalid: should be < 3
          chunkSize: 4,
        },
        data: new Uint8Array([0xAA, 0xBB, 0xCC, 0xDD]),
      };

      expect(parser.validatePacket(packet)).toBe(false);
    });

    it('should reject packet with mismatched data size', () => {
      const packet = {
        header: {
          magic: 0xFFD8,
          frameId: 1,
          totalChunks: 3,
          chunkId: 0,
          chunkSize: 10, // Says 10 bytes
        },
        data: new Uint8Array([0xAA, 0xBB, 0xCC, 0xDD]), // Only 4 bytes
      };

      expect(parser.validatePacket(packet)).toBe(false);
    });

    it('should validate first chunk', () => {
      const packet = {
        header: {
          magic: 0xFFD8,
          frameId: 1,
          totalChunks: 5,
          chunkId: 0,
          chunkSize: 2,
        },
        data: new Uint8Array([0xAA, 0xBB]),
      };

      expect(parser.validatePacket(packet)).toBe(true);
    });

    it('should validate last chunk', () => {
      const packet = {
        header: {
          magic: 0xFFD8,
          frameId: 1,
          totalChunks: 5,
          chunkId: 4,
          chunkSize: 2,
        },
        data: new Uint8Array([0xAA, 0xBB]),
      };

      expect(parser.validatePacket(packet)).toBe(true);
    });
  });

  describe('getPacketInfo', () => {
    it('should return human-readable packet info', () => {
      const packet = {
        header: {
          magic: 0xFFD8,
          frameId: 42,
          totalChunks: 5,
          chunkId: 2,
          chunkSize: 1024,
        },
        data: new Uint8Array(1024),
      };

      const info = parser.getPacketInfo(packet);
      expect(info).toContain('Frame 42');
      expect(info).toContain('Chunk 3/5'); // chunkId 2 is the 3rd chunk (0-indexed)
      expect(info).toContain('1024B');
    });
  });
});
