/// Optional protected read-only diagnostics. No control or power commands.
class BleDiagnostics {
  static const uuid = '4d89f6a0-73b9-4f14-9d3e-63b2145a0006';
  const BleDiagnostics({
    required this.resetReason,
    required this.lastStop,
    required this.faults,
    required this.uptimeSeconds,
    required this.disconnectCount,
    required this.leaseExpiryCount,
    required this.notificationFailureCount,
    required this.lastGapReason,
  });
  factory BleDiagnostics.decode(List<int> bytes) {
    if (bytes.length != 20 ||
        bytes.any((x) => x < 0 || x > 255) ||
        bytes[0] != 1 ||
        bytes[2] > 8 ||
        (bytes[3] & ~31) != 0 ||
        bytes[18] != 0 ||
        bytes[19] != 0) {
      throw const FormatException('Invalid diagnostics');
    }
    int u16(int i) => bytes[i] | (bytes[i + 1] << 8);
    int u32(int i) => u16(i) | (u16(i + 2) << 16);
    return BleDiagnostics(
      resetReason: bytes[1],
      lastStop: bytes[2],
      faults: bytes[3],
      uptimeSeconds: u32(4),
      disconnectCount: u32(8),
      leaseExpiryCount: u16(12),
      notificationFailureCount: u16(14),
      lastGapReason: u16(16),
    );
  }
  final int resetReason,
      lastStop,
      faults,
      uptimeSeconds,
      disconnectCount,
      leaseExpiryCount,
      notificationFailureCount,
      lastGapReason;
  Map<String, Object?> toJson() => {
    'resetReason': resetReason,
    'lastStop': lastStop,
    'faults': faults,
    'uptimeSeconds': uptimeSeconds,
    'disconnectCount': disconnectCount,
    'leaseExpiryCount': leaseExpiryCount,
    'notificationFailureCount': notificationFailureCount,
    'lastGapReason': lastGapReason,
  };
}
