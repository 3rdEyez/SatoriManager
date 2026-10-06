/// User-facing control state derived only from structured snapshot fields.
String controlStatus(Map state) {
  switch (state['endState']) {
    case 'ending':
      return '正在结束拍摄…';
    case 'confirmed':
      return '拍摄已结束，控制已释放';
    case 'unconfirmed':
      return '拍摄已结束，设备停止未确认';
    case 'localOnly':
      return '本机拍摄已结束';
  }
  switch (state['connection']) {
    case 'connected':
      return switch (state['controlPhase']) {
        'pausing' => '暂停中…',
        'pauseUnconfirmed' => '暂停未确认',
        'configurationError' => '设备配置异常，暂时无法控制',
        'outputUnconfirmed' => '控制状态未确认',
        'active' =>
          state['autoRotate'] == true || state['autoWink'] == true
              ? '自动控制中'
              : state['playback'] == 'playing'
              ? '动作播放中'
              : '控制中',
        'paused' => '已暂停',
        'ready' => '已暂停',
        'actionFailed' => '动作已停止',
        _ => '正在准备…',
      };
    case 'reconnecting':
      return '正在重新连接…';
    case 'connecting':
      return '正在连接…';
    case 'searching':
      return '正在搜索…';
    case 'failed':
      if (state['issueCode'] == 'versionMismatch') return '版本不兼容';
      return '连接失败';
    default:
      return '未连接';
  }
}

bool needsControlAttention(Map state) =>
    state['endState'] == 'unconfirmed' ||
    state['controlPhase'] == 'pauseUnconfirmed' ||
    state['controlPhase'] == 'configurationError' ||
    state['controlPhase'] == 'outputUnconfirmed' ||
    state['controlPhase'] == 'actionFailed';

String diagnosticStopReason(int? reason) => switch (reason) {
  0 => '本次启动尚无停止记录',
  1 => '收到暂停操作',
  2 => '收到结束／释放控制操作',
  3 => '蓝牙连接中断',
  4 => '控制心跳超时',
  5 => '舵机输出驱动异常',
  6 => '配对存储异常',
  7 => '控制队列异常',
  8 => '蓝牙服务重置',
  _ => '未知',
};

String diagnosticFaults(int flags) {
  final faults = [
    if (flags & 1 != 0) '舵机输出驱动异常',
    if (flags & 2 != 0) '配对存储异常',
    if (flags & 4 != 0) '控制队列异常',
    if (flags & 8 != 0) '设备身份存储异常',
    if (flags & 16 != 0) '启动姿态配置无效',
  ];
  return faults.isEmpty ? '未记录故障' : faults.join('、');
}

bool diagnosticsAreFresh(Map state, {DateTime? now}) {
  final sampled = DateTime.tryParse(state['diagnosticsAt']?.toString() ?? '');
  if (sampled == null || state['connection'] != 'connected') return false;
  final age = (now ?? DateTime.now()).difference(sampled);
  return age >= Duration.zero && age <= const Duration(seconds: 15);
}
