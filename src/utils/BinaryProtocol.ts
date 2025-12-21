/**
 * Binary Protocol Utilities
 *
 * Utilities for parsing binary data in little-endian format
 * Used for TCP video streaming protocol from ESP32
 */

const JPEG_MAGIC_NUMBER = 0xFFD8;
const PACKET_HEADER_SIZE = 12;

/**
 * Read a 16-bit unsigned integer in little-endian format
 */
export function readUint16LE(buffer: Uint8Array, offset: number): number {
  return buffer[offset] | (buffer[offset + 1] << 8);
}

/**
 * Read a 32-bit unsigned integer in little-endian format
 */
export function readUint32LE(buffer: Uint8Array, offset: number): number {
  return (
    buffer[offset] |
    (buffer[offset + 1] << 8) |
    (buffer[offset + 2] << 16) |
    (buffer[offset + 3] << 24)
  ) >>> 0; // >>> 0 ensures unsigned
}

/**
 * Validate JPEG magic number (0xFFD8)
 */
export function validateMagicNumber(buffer: Uint8Array): boolean {
  if (buffer.length < 2) {
    return false;
  }
  const magic = readUint16LE(buffer, 0);
  return magic === JPEG_MAGIC_NUMBER;
}

/**
 * Frame packet header structure
 * Total size: 12 bytes
 *
 * Layout:
 * - Magic (2 bytes): 0xFFD8 (JPEG magic)
 * - Frame ID (4 bytes): Unique frame identifier
 * - Total Chunks (2 bytes): Total number of chunks in this frame
 * - Chunk ID (2 bytes): Current chunk index (0-based)
 * - Chunk Size (2 bytes): Size of data following this header
 */
export interface FramePacketHeader {
  magic: number;
  frameId: number;
  totalChunks: number;
  chunkId: number;
  chunkSize: number;
}

/**
 * Parse a 12-byte packet header
 *
 * @param buffer - Buffer containing at least 12 bytes
 * @returns Parsed header or null if invalid
 */
export function parsePacketHeader(buffer: Uint8Array): FramePacketHeader | null {
  if (buffer.length < PACKET_HEADER_SIZE) {
    return null;
  }

  const magic = readUint16LE(buffer, 0);

  // Validate magic number
  if (magic !== JPEG_MAGIC_NUMBER) {
    return null;
  }

  const frameId = readUint32LE(buffer, 2);
  const totalChunks = readUint16LE(buffer, 6);
  const chunkId = readUint16LE(buffer, 8);
  const chunkSize = readUint16LE(buffer, 10);

  // Validate header values
  if (totalChunks === 0 || chunkId >= totalChunks || chunkSize === 0) {
    return null;
  }

  return {
    magic,
    frameId,
    totalChunks,
    chunkId,
    chunkSize,
  };
}

/**
 * Get the expected packet header size
 */
export function getPacketHeaderSize(): number {
  return PACKET_HEADER_SIZE;
}

/**
 * Get the JPEG magic number constant
 */
export function getJpegMagicNumber(): number {
  return JPEG_MAGIC_NUMBER;
}
