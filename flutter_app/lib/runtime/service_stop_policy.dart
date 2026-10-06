import 'dart:async';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// The plugin reports failures as values, not only as thrown exceptions.
/// A completed await therefore is not enough to confirm a service has stopped.
Future<void> stopServiceChecked(
  Future<ServiceRequestResult> Function() stop, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  const message = '控制结束请求已接收，但后台服务停止未确认；请刷新状态';
  try {
    final result = await stop().timeout(timeout);
    if (result is! ServiceRequestSuccess) throw StateError(message);
  } catch (_) {
    throw StateError(message);
  }
}
