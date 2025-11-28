import {MD3DarkTheme} from 'react-native-paper';
import type {MD3Theme} from 'react-native-paper';

// Satori Theme 配色
export const Colors = {
  // 主色调 - 洋红色系
  primary: '#FF00FF',        // Magenta
  primaryLight: '#FF66FF',
  primaryDark: '#CC00CC',
  primaryGlow: 'rgba(255, 0, 255, 0.5)',

  // 次要色 - 青色/写轮眼
  secondary: '#00FFFF',      // Cyan
  secondaryDark: '#00CCCC',
  secondaryGlow: 'rgba(0, 255, 255, 0.5)',

  // 背景色 - 深紫色系
  background: '#0D0015',     // 极深紫黑
  backgroundLight: '#1A0028',
  backgroundDark: '#050008',
  surface: 'rgba(255, 0, 255, 0.05)',
  surfaceHighlight: 'rgba(255, 0, 255, 0.1)',

  // 状态色
  success: '#00FF88',        // 霓虹绿
  successLight: 'rgba(0, 255, 136, 0.15)',
  error: '#FF0044',          // 血红
  errorLight: 'rgba(255, 0, 68, 0.15)',
  warning: '#FFAA00',        // 琥珀
  warningLight: 'rgba(255, 170, 0, 0.15)',

  // 文字色
  text: '#FFFFFF',
  textSecondary: 'rgba(255, 255, 255, 0.7)',
  textMuted: 'rgba(255, 255, 255, 0.5)',
  textDisabled: 'rgba(255, 255, 255, 0.3)',

  // 特效色
  glow: 'rgba(255, 0, 255, 0.6)',
  glowCyan: 'rgba(0, 255, 255, 0.8)',
  glowBlood: 'rgba(255, 0, 68, 0.6)',
  overlay: 'rgba(13, 0, 21, 0.9)',

  // 神经/血管纹理色
  nerve: 'rgba(255, 0, 255, 0.15)',
  synapse: 'rgba(0, 255, 255, 0.1)',

  // 边框色
  border: 'rgba(255, 0, 255, 0.2)',
  borderLight: 'rgba(255, 0, 255, 0.3)',
  borderCyan: 'rgba(0, 255, 255, 0.3)',

  // 电池状态色
  batteryFull: '#00FF88',
  batteryMedium: '#FFAA00',
  batteryLow: '#FF4400',
  batteryCritical: '#FF0044',

  // 心跳色
  heartbeat: '#FF0066',
  heartbeatGlow: 'rgba(255, 0, 102, 0.5)',
};

// 间距常量
export const Spacing = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 20,
  xxl: 24,
  xxxl: 32,
};

// 圆角常量
export const BorderRadius = {
  sm: 8,
  md: 12,
  lg: 16,
  xl: 20,
  xxl: 24,
  full: 999,
};

// 字体大小
export const FontSize = {
  xs: 10,
  sm: 12,
  md: 14,
  lg: 16,
  xl: 18,
  xxl: 20,
  xxxl: 24,
  title: 28,
  hero: 36,
};

// 阴影样式
export const Shadows = {
  sm: {
    shadowColor: Colors.primary,
    shadowOffset: {width: 0, height: 2},
    shadowOpacity: 0.2,
    shadowRadius: 4,
    elevation: 2,
  },
  md: {
    shadowColor: Colors.primary,
    shadowOffset: {width: 0, height: 4},
    shadowOpacity: 0.3,
    shadowRadius: 8,
    elevation: 4,
  },
  lg: {
    shadowColor: Colors.primary,
    shadowOffset: {width: 0, height: 6},
    shadowOpacity: 0.4,
    shadowRadius: 12,
    elevation: 8,
  },
  glow: {
    shadowColor: Colors.primary,
    shadowOffset: {width: 0, height: 0},
    shadowOpacity: 0.6,
    shadowRadius: 20,
    elevation: 10,
  },
  cyanGlow: {
    shadowColor: Colors.secondary,
    shadowOffset: {width: 0, height: 0},
    shadowOpacity: 0.6,
    shadowRadius: 20,
    elevation: 10,
  },
};

// 动画持续时间
export const AnimationDuration = {
  instant: 100,
  fast: 150,
  normal: 300,
  slow: 500,
  heartbeat: 800,
};

// 状态文案 (彩蛋)
export const StatusMessages = {
  connecting: '意识同步中...',
  connected: '心智已连接',
  disconnected: '心智连接中断',
  scanning: '探测意识波...',
  error: '同步异常',
  lowBattery: '能量不足，请补充',
  criticalBattery: '⚠ 生命体征危急',
  heartbeatNormal: '脉搏正常',
  heartbeatWeak: '脉搏微弱',
  heartbeatLost: '脉搏消失',
  reviving: '电击复苏中...',
};

// React Native Paper 自定义暗色主题 - Satori Theme
export const paperTheme: MD3Theme = {
  ...MD3DarkTheme,
  colors: {
    ...MD3DarkTheme.colors,
    primary: Colors.primary,
    primaryContainer: Colors.primaryDark,
    secondary: Colors.secondary,
    secondaryContainer: Colors.secondaryDark,
    tertiary: Colors.warning,
    tertiaryContainer: Colors.warningLight,
    surface: Colors.backgroundLight,
    surfaceVariant: Colors.surfaceHighlight,
    surfaceDisabled: Colors.surface,
    background: Colors.background,
    error: Colors.error,
    errorContainer: Colors.errorLight,
    onPrimary: Colors.backgroundDark,
    onPrimaryContainer: Colors.text,
    onSecondary: Colors.backgroundDark,
    onSecondaryContainer: Colors.text,
    onTertiary: Colors.backgroundDark,
    onTertiaryContainer: Colors.text,
    onSurface: Colors.text,
    onSurfaceVariant: Colors.textSecondary,
    onSurfaceDisabled: Colors.textDisabled,
    onError: Colors.text,
    onErrorContainer: Colors.text,
    onBackground: Colors.text,
    outline: Colors.border,
    outlineVariant: Colors.borderLight,
    inverseSurface: Colors.text,
    inverseOnSurface: Colors.background,
    inversePrimary: Colors.primaryDark,
    shadow: '#000000',
    scrim: Colors.overlay,
    backdrop: Colors.overlay,
    elevation: {
      level0: 'transparent',
      level1: Colors.backgroundLight,
      level2: Colors.surfaceHighlight,
      level3: 'rgba(255, 0, 255, 0.08)',
      level4: 'rgba(255, 0, 255, 0.10)',
      level5: 'rgba(255, 0, 255, 0.12)',
    },
  },
  roundness: 3,
};
