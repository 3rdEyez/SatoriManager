/**
 * Frame Packet Parser
 *
 * Parses binary TCP video packets with 12-byte headers
 */

import {
  parsePacketHeader,
  getPacketHeaderSize,
  type FramePacketHeader,
} from '../utils/BinaryProtocol';

export interface ParsedPacket {
  header: FramePacketHeader;
  data: Uint8Array;
}

export class FramePacketParser {
  /**
   * Parse a complete packet (header + data)
   *
   * @param buffer - Buffer containing header and data
   * @returns Parsed packet or null if invalid
   */
  parsePacket(buffer: Uint8Array): ParsedPacket | null {
    const headerSize = getPacketHeaderSize();

    // Check if buffer has at least header
    if (buffer.length < headerSize) {
      console.warn(
        `[FramePacketParser] Buffer too small: ${buffer.length} < ${headerSize}`
      );
      return null;
    }

    // Parse header
    const header = parsePacketHeader(buffer);
    if (!header) {
      console.warn('[FramePacketParser] Invalid packet header');
      return null;
    }

    // Check if buffer has complete data
    const expectedSize = headerSize + header.chunkSize;
    if (buffer.length < expectedSize) {
      console.warn(
        `[FramePacketParser] Incomplete packet: ${buffer.length} < ${expectedSize}`
      );
      return null;
    }

    // Extract data
    const data = buffer.slice(headerSize, headerSize + header.chunkSize);

    return {
      header,
      data,
    };
  }

  /**
   * Parse only the header from a buffer
   *
   * @param buffer - Buffer containing at least the header
   * @returns Parsed header or null if invalid
   */
  parseHeader(buffer: Uint8Array): FramePacketHeader | null {
    return parsePacketHeader(buffer);
  }

  /**
   * Get the expected packet size from a header
   *
   * @param header - Parsed header
   * @returns Total packet size (header + data)
   */
  getExpectedPacketSize(header: FramePacketHeader): number {
    return getPacketHeaderSize() + header.chunkSize;
  }

  /**
   * Validate a parsed packet
   *
   * @param packet - Parsed packet
   * @returns True if packet is valid
   */
  validatePacket(packet: ParsedPacket): boolean {
    const { header, data } = packet;

    // Check chunk ID is within range
    if (header.chunkId >= header.totalChunks) {
      console.warn(
        `[FramePacketParser] Invalid chunk ID: ${header.chunkId} >= ${header.totalChunks}`
      );
      return false;
    }

    // Check data size matches header
    if (data.length !== header.chunkSize) {
      console.warn(
        `[FramePacketParser] Data size mismatch: ${data.length} !== ${header.chunkSize}`
      );
      return false;
    }

    return true;
  }

  /**
   * Get packet statistics for debugging
   *
   * @param packet - Parsed packet
   * @returns Human-readable packet info
   */
  getPacketInfo(packet: ParsedPacket): string {
    const { header, data } = packet;
    return `Frame ${header.frameId}, Chunk ${header.chunkId + 1}/${header.totalChunks}, Size ${data.length}B`;
  }
}

// Singleton instance
let parserInstance: FramePacketParser | null = null;

/**
 * Get the singleton instance of FramePacketParser
 */
export function getFramePacketParser(): FramePacketParser {
  if (!parserInstance) {
    parserInstance = new FramePacketParser();
  }
  return parserInstance;
}
