/// User-facing control state derived only from structured snapshot fields.
String controlStatus(Map state) {
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
    state['controlPhase'] == 'pauseUnconfirmed' ||
    state['controlPhase'] == 'configurationError' ||
    state['controlPhase'] == 'outputUnconfirmed' ||
    state['controlPhase'] == 'actionFailed';
