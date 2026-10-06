/// Accept only live replies or broadcasts from the already synchronized runtime.
/// An expired reply must not make stale state look newly received.
bool acceptsTaskMessage(
  Map data, {
  required String clientId,
  required String? runtimeId,
  required Map<int, String> pendingOperations,
  required Set<String> retiredRuntimes,
}) {
  if (data['clientId'] != null && data['clientId'] != clientId) return false;
  if (data['id'] != null && !pendingOperations.containsKey(data['id'])) {
    return false;
  }
  final raw = data['data'] ?? data['snapshot'];
  if (raw is! Map) return true;
  final incomingRuntime = raw['runtimeId'];
  if (incomingRuntime is! String || retiredRuntimes.contains(incomingRuntime)) {
    return false;
  }
  return incomingRuntime == runtimeId ||
      (data['clientId'] == clientId &&
          pendingOperations[data['id']] == 'snapshot');
}
