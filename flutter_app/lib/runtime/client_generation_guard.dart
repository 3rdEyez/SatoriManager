/// Keeps foreground UI messages scoped to the currently attached UI client.
/// A snapshot is a handshake: it may take ownership without touching the
/// service-owned engine. Once retired, a client can never reclaim the runtime.
class ClientGenerationGuard {
  String? _activeClientId;
  final Set<String> retiredClientIds = {};

  String? get activeClientId => _activeClientId;

  String? authorize(Map message, {required String runtimeId}) {
    final clientId = message['clientId'];
    final operation = message['op'];
    if (clientId is! String || clientId.isEmpty) {
      return '界面会话标识无效，请刷新状态';
    }

    if (operation == 'snapshot') {
      if (retiredClientIds.contains(clientId)) {
        return '旧界面会话已结束，请刷新状态';
      }
      final active = _activeClientId;
      if (active != null && active != clientId) {
        retiredClientIds.add(active);
      }
      _activeClientId = clientId;
      return null;
    }

    if (_activeClientId == null) {
      return '请先同步后台会话状态';
    }
    if (retiredClientIds.contains(clientId) || clientId != _activeClientId) {
      return '界面会话已更新，请刷新后重试';
    }
    if (message['expectedRuntimeId'] != runtimeId) {
      return '后台会话已变化，请刷新状态后重试';
    }
    return null;
  }
}
