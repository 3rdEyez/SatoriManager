/**
 * ByteBuffer - A utility class for reading binary data
 *
 * Provides convenient methods for reading different data types
 * from a Uint8Array buffer with little-endian byte order
 */

export class ByteBuffer {
  private buffer: Uint8Array;
  private position: number;

  constructor(buffer: Uint8Array) {
    this.buffer = buffer;
    this.position = 0;
  }

  /**
   * Get the current read position
   */
  getPosition(): number {
    return this.position;
  }

  /**
   * Set the read position
   */
  setPosition(position: number): void {
    if (position < 0 || position > this.buffer.length) {
      throw new Error(`Invalid position: ${position}`);
    }
    this.position = position;
  }

  /**
   * Get the number of bytes remaining from current position
   */
  remaining(): number {
    return this.buffer.length - this.position;
  }

  /**
   * Check if there are bytes remaining
   */
  hasRemaining(): boolean {
    return this.position < this.buffer.length;
  }

  /**
   * Get the total buffer length
   */
  length(): number {
    return this.buffer.length;
  }

  /**
   * Read a single byte (uint8)
   */
  readUint8(): number {
    if (this.remaining() < 1) {
      throw new Error('Buffer underflow: cannot read uint8');
    }
    return this.buffer[this.position++];
  }

  /**
   * Read a 16-bit unsigned integer in little-endian format
   */
  readUint16LE(): number {
    if (this.remaining() < 2) {
      throw new Error('Buffer underflow: cannot read uint16');
    }
    const value = this.buffer[this.position] | (this.buffer[this.position + 1] << 8);
    this.position += 2;
    return value;
  }

  /**
   * Read a 32-bit unsigned integer in little-endian format
   */
  readUint32LE(): number {
    if (this.remaining() < 4) {
      throw new Error('Buffer underflow: cannot read uint32');
    }
    const value =
      (this.buffer[this.position] |
        (this.buffer[this.position + 1] << 8) |
        (this.buffer[this.position + 2] << 16) |
        (this.buffer[this.position + 3] << 24)) >>>
      0; // >>> 0 ensures unsigned
    this.position += 4;
    return value;
  }

  /**
   * Read a slice of bytes without advancing position
   */
  peek(length: number): Uint8Array {
    if (this.remaining() < length) {
      throw new Error(`Buffer underflow: cannot peek ${length} bytes`);
    }
    return this.buffer.slice(this.position, this.position + length);
  }

  /**
   * Read a slice of bytes and advance position
   */
  readBytes(length: number): Uint8Array {
    if (this.remaining() < length) {
      throw new Error(`Buffer underflow: cannot read ${length} bytes`);
    }
    const slice = this.buffer.slice(this.position, this.position + length);
    this.position += length;
    return slice;
  }

  /**
   * Skip a number of bytes
   */
  skip(count: number): void {
    if (this.remaining() < count) {
      throw new Error(`Buffer underflow: cannot skip ${count} bytes`);
    }
    this.position += count;
  }

  /**
   * Reset position to beginning
   */
  reset(): void {
    this.position = 0;
  }

  /**
   * Get the underlying buffer
   */
  getBuffer(): Uint8Array {
    return this.buffer;
  }

  /**
   * Create a new ByteBuffer from a slice of this buffer
   */
  slice(start: number, end?: number): ByteBuffer {
    return new ByteBuffer(this.buffer.slice(start, end));
  }

  /**
   * Convert remaining bytes to hex string (for debugging)
   */
  toHexString(maxBytes: number = 16): string {
    const bytes = this.buffer.slice(
      this.position,
      Math.min(this.position + maxBytes, this.buffer.length)
    );
    return Array.from(bytes)
      .map(b => b.toString(16).padStart(2, '0'))
      .join(' ');
  }
}
