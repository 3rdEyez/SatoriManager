import React, {useCallback, useRef, useState} from 'react';
import {View, StyleSheet, Animated} from 'react-native';
import {SafeAreaView} from 'react-native-safe-area-context';
import {Text, Button, Chip, Surface} from 'react-native-paper';
import {GestureDetector, Gesture, GestureHandlerRootView} from 'react-native-gesture-handler';
import Svg, {Circle, Path, G, Defs, RadialGradient, Stop} from 'react-native-svg';
import Icon from 'react-native-vector-icons/MaterialCommunityIcons';
import {useAppStore} from '../store/appStore';
import {ActionMacros, EyeMode} from '../types';
import {Colors, Spacing, BorderRadius, StatusMessages} from '../theme';

// 写轮眼风格摇杆组件
const SharinganJoystick: React.FC<{
  size?: number;
  onMove?: (x: number, y: number) => void;
  onRelease?: () => void;
  disabled?: boolean;
}> = ({size = 280, onMove, onRelease, disabled = false}) => {
  const translateX = useRef(new Animated.Value(0)).current;
  const translateY = useRef(new Animated.Value(0)).current;
  const scale = useRef(new Animated.Value(1)).current;
  const [isActive, setIsActive] = useState(false);

  const innerSize = 70;
  const maxDistance = (size - innerSize) / 2 - 20;
  const center = size / 2;

  const clampPosition = useCallback(
    (x: number, y: number) => {
      const distance = Math.sqrt(x * x + y * y);
      if (distance > maxDistance) {
        const ratio = maxDistance / distance;
        return {x: x * ratio, y: y * ratio};
      }
      return {x, y};
    },
    [maxDistance],
  );

  const panGesture = Gesture.Pan()
    .enabled(!disabled)
    .onStart(() => {
      setIsActive(true);
      Animated.spring(scale, {
        toValue: 1.1,
        useNativeDriver: true,
      }).start();
    })
    .onUpdate((event) => {
      const clamped = clampPosition(event.translationX, event.translationY);
      translateX.setValue(clamped.x);
      translateY.setValue(clamped.y);

      const normalizedX = clamped.x / maxDistance;
      const normalizedY = -clamped.y / maxDistance;
      onMove?.(normalizedX, normalizedY);
    })
    .onEnd(() => {
      setIsActive(false);
      Animated.parallel([
        Animated.spring(translateX, {
          toValue: 0,
          useNativeDriver: true,
          tension: 80,
          friction: 8,
        }),
        Animated.spring(translateY, {
          toValue: 0,
          useNativeDriver: true,
          tension: 80,
          friction: 8,
        }),
        Animated.spring(scale, {
          toValue: 1,
          useNativeDriver: true,
        }),
      ]).start();
      onMove?.(0, 0);
      onRelease?.();
    });

  // 写轮眼纹路
  const renderTomoe = (angle: number, key: number) => {
    const radius = size / 2 - 50;
    const x = center + radius * 0.5 * Math.cos((angle * Math.PI) / 180);
    const y = center + radius * 0.5 * Math.sin((angle * Math.PI) / 180);
    return (
      <G key={key} transform={`rotate(${angle + 90}, ${x}, ${y})`}>
        <Circle cx={x} cy={y} r={12} fill={Colors.primary} opacity={0.8} />
        <Path
          d={`M ${x} ${y - 12} Q ${x + 15} ${y} ${x} ${y + 20}`}
          fill={Colors.primary}
          opacity={0.6}
        />
      </G>
    );
  };

  return (
    <GestureHandlerRootView style={styles.joystickGestureRoot}>
      <View style={[styles.joystickContainer, {width: size, height: size}]}>
        <Svg width={size} height={size}>
          <Defs>
            <RadialGradient id="eyeGrad" cx="50%" cy="50%" r="50%">
              <Stop offset="0%" stopColor={Colors.error} stopOpacity="0.3" />
              <Stop offset="70%" stopColor={Colors.backgroundDark} stopOpacity="0.8" />
              <Stop offset="100%" stopColor={Colors.background} stopOpacity="1" />
            </RadialGradient>
          </Defs>

          {/* 外圈 - 血轮眼边缘 */}
          <Circle
            cx={center}
            cy={center}
            r={size / 2 - 5}
            fill="none"
            stroke={isActive ? Colors.primary : Colors.border}
            strokeWidth={3}
          />

          {/* 虹膜背景 */}
          <Circle
            cx={center}
            cy={center}
            r={size / 2 - 20}
            fill="url(#eyeGrad)"
          />

          {/* 写轮眼纹路 - 三勾玉 */}
          {[0, 120, 240].map((angle, i) => renderTomoe(angle, i))}

          {/* 内圈 */}
          <Circle
            cx={center}
            cy={center}
            r={size / 4}
            fill="none"
            stroke={Colors.border}
            strokeWidth={1}
            strokeDasharray="5,5"
          />
        </Svg>

        {/* 可拖动的瞳孔 */}
        <GestureDetector gesture={panGesture}>
          <Animated.View
            style={[
              styles.pupil,
              {
                width: innerSize,
                height: innerSize,
                borderRadius: innerSize / 2,
                transform: [
                  {translateX},
                  {translateY},
                  {scale},
                ],
                opacity: disabled ? 0.5 : 1,
              },
            ]}>
            <View style={styles.pupilInner}>
              <View style={styles.pupilHighlight} />
            </View>
          </Animated.View>
        </GestureDetector>
      </View>
    </GestureHandlerRootView>
  );
};

const PuppeteerScreen: React.FC = () => {
  const {
    connection,
    currentMode,
    setJoystickPosition,
    executeAction,
    switchMode,
  } = useAppStore();

  const [lastPosition, setLastPosition] = useState({x: 0, y: 0});
  const lastSendTime = useRef(0);

  const handleJoystickMove = useCallback(
    (x: number, y: number) => {
      const now = Date.now();
      // 频率限制：50ms
      if (now - lastSendTime.current >= 50) {
        setJoystickPosition({x, y});
        setLastPosition({x, y});
        lastSendTime.current = now;
      }
    },
    [setJoystickPosition],
  );

  const handleMacro = (macroKey: string) => {
    const macro = ActionMacros[macroKey];
    if (macro) {
      executeAction(macroKey);
    }
  };

  const isManualMode = currentMode === EyeMode.Manual;

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.content}>
        {/* 标题 */}
        <View style={styles.header}>
          <Text variant="headlineMedium" style={styles.title}>
            操控连接
          </Text>
          <Text variant="bodySmall" style={styles.subtitle}>
            {connection.isConnected ? 'Puppeteer Mode' : StatusMessages.disconnected}
          </Text>
        </View>

        {/* 模式切换 */}
        <View style={styles.modeToggle}>
          <Button
            mode={isManualMode ? 'contained' : 'outlined'}
            onPress={() => switchMode(EyeMode.Manual)}
            disabled={!connection.isConnected}
            icon="gesture-tap"
            compact
            style={styles.modeButton}>
            手动
          </Button>
          <Button
            mode={!isManualMode && currentMode === EyeMode.Auto ? 'contained' : 'outlined'}
            onPress={() => switchMode(EyeMode.Auto)}
            disabled={!connection.isConnected}
            icon="eye-refresh"
            compact
            style={styles.modeButton}>
            自动
          </Button>
        </View>

        {/* 位置显示 */}
        <View style={styles.positionDisplay}>
          <Chip icon="axis-x-arrow" style={styles.positionChip}>
            Yaw: {(lastPosition.x * 100).toFixed(0)}%
          </Chip>
          <Chip icon="axis-y-arrow" style={styles.positionChip}>
            Pitch: {(lastPosition.y * 100).toFixed(0)}%
          </Chip>
        </View>

        {/* 写轮眼摇杆 */}
        <View style={styles.joystickArea}>
          <SharinganJoystick
            size={280}
            onMove={handleJoystickMove}
            disabled={!connection.isConnected || !isManualMode}
          />
        </View>

        {/* 预设动作宏 */}
        <View style={styles.macroSection}>
          <Text variant="titleSmall" style={styles.sectionTitle}>
            预设动作
          </Text>
          <View style={styles.macroGrid}>
            {Object.entries(ActionMacros).map(([key, macro]) => (
              <Button
                key={key}
                mode="elevated"
                onPress={() => handleMacro(key)}
                disabled={!connection.isConnected}
                style={styles.macroButton}
                labelStyle={styles.macroLabel}
                compact>
                {macro.name}
              </Button>
            ))}
          </View>
        </View>
      </View>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.background,
  },
  content: {
    flex: 1,
    padding: Spacing.lg,
  },
  header: {
    alignItems: 'center',
    marginBottom: Spacing.md,
  },
  title: {
    color: Colors.secondary,
    fontWeight: 'bold',
    textShadowColor: Colors.secondaryGlow,
    textShadowRadius: 10,
  },
  subtitle: {
    color: Colors.textMuted,
    marginTop: Spacing.xs,
  },
  modeToggle: {
    flexDirection: 'row',
    justifyContent: 'center',
    gap: Spacing.md,
    marginBottom: Spacing.md,
  },
  modeButton: {
    minWidth: 100,
  },
  positionDisplay: {
    flexDirection: 'row',
    justifyContent: 'center',
    gap: Spacing.md,
    marginBottom: Spacing.md,
  },
  positionChip: {
    backgroundColor: Colors.backgroundLight,
  },
  joystickArea: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  joystickGestureRoot: {
    flex: 0,
  },
  joystickContainer: {
    justifyContent: 'center',
    alignItems: 'center',
  },
  pupil: {
    position: 'absolute',
    backgroundColor: Colors.backgroundDark,
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 3,
    borderColor: Colors.primary,
    shadowColor: Colors.primary,
    shadowOffset: {width: 0, height: 0},
    shadowOpacity: 0.8,
    shadowRadius: 15,
    elevation: 10,
  },
  pupilInner: {
    width: '70%',
    height: '70%',
    borderRadius: 100,
    backgroundColor: Colors.background,
    justifyContent: 'center',
    alignItems: 'center',
  },
  pupilHighlight: {
    width: 15,
    height: 15,
    borderRadius: 10,
    backgroundColor: 'rgba(255, 255, 255, 0.4)',
    position: 'absolute',
    top: 8,
    right: 8,
  },
  macroSection: {
    paddingTop: Spacing.lg,
  },
  sectionTitle: {
    color: Colors.textSecondary,
    marginBottom: Spacing.sm,
    textAlign: 'center',
  },
  macroGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'center',
    gap: Spacing.sm,
  },
  macroButton: {
    minWidth: 80,
    backgroundColor: Colors.backgroundLight,
  },
  macroLabel: {
    fontSize: 12,
  },
});

export default PuppeteerScreen;
