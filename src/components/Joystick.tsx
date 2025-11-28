import React, {useCallback, useRef} from 'react';
import {View, StyleSheet, Animated} from 'react-native';
import {
  GestureDetector,
  Gesture,
  GestureHandlerRootView,
} from 'react-native-gesture-handler';
import Svg, {Circle, Path} from 'react-native-svg';
import {Colors, Shadows} from '../theme';

interface JoystickProps {
  size?: number;
  innerSize?: number;
  onMove?: (x: number, y: number) => void;
  onRelease?: () => void;
  battery?: number;
  resetOnRelease?: boolean;
}

const Joystick: React.FC<JoystickProps> = ({
  size = 200,
  innerSize = 60,
  onMove,
  onRelease,
  battery = 0,
  resetOnRelease = true,
}) => {
  const translateX = useRef(new Animated.Value(0)).current;
  const translateY = useRef(new Animated.Value(0)).current;
  const currentX = useRef(0);
  const currentY = useRef(0);

  const maxDistance = (size - innerSize) / 2;

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
    .onUpdate((event) => {
      const clamped = clampPosition(event.translationX, event.translationY);
      currentX.current = clamped.x;
      currentY.current = clamped.y;
      translateX.setValue(clamped.x);
      translateY.setValue(clamped.y);

      // 归一化为 -1 到 1
      const normalizedX = clamped.x / maxDistance;
      const normalizedY = -clamped.y / maxDistance; // 反转 Y 轴
      onMove?.(normalizedX, normalizedY);
    })
    .onEnd(() => {
      if (resetOnRelease) {
        Animated.spring(translateX, {
          toValue: 0,
          useNativeDriver: true,
          tension: 100,
          friction: 10,
        }).start();
        Animated.spring(translateY, {
          toValue: 0,
          useNativeDriver: true,
          tension: 100,
          friction: 10,
        }).start();
        currentX.current = 0;
        currentY.current = 0;
        onMove?.(0, 0);
      }
      onRelease?.();
    });

  // 电量弧形路径
  const batteryArcPath = useCallback(() => {
    const radius = size / 2 - 8;
    const centerX = size / 2;
    const centerY = size / 2;
    const startAngle = -90; // 从顶部开始
    const endAngle = startAngle + (battery / 100) * 360;

    const startRad = (startAngle * Math.PI) / 180;
    const endRad = (endAngle * Math.PI) / 180;

    const x1 = centerX + radius * Math.cos(startRad);
    const y1 = centerY + radius * Math.sin(startRad);
    const x2 = centerX + radius * Math.cos(endRad);
    const y2 = centerY + radius * Math.sin(endRad);

    const largeArcFlag = battery > 50 ? 1 : 0;

    return `M ${x1} ${y1} A ${radius} ${radius} 0 ${largeArcFlag} 1 ${x2} ${y2}`;
  }, [size, battery]);

  return (
    <GestureHandlerRootView style={styles.gestureRoot}>
      <View style={[styles.container, {width: size, height: size}]}>
        {/* 外圈和电量指示 */}
        <Svg width={size} height={size} style={styles.svgOverlay}>
          {/* 背景圆环 */}
          <Circle
            cx={size / 2}
            cy={size / 2}
            r={size / 2 - 8}
            fill="none"
            stroke={Colors.borderLight}
            strokeWidth={4}
          />
          {/* 电量弧线 */}
          {battery > 0 && (
            <Path
              d={batteryArcPath()}
              fill="none"
              stroke={Colors.glowCyan}
              strokeWidth={4}
              strokeLinecap="round"
            />
          )}
          {/* 内部背景圆 */}
          <Circle
            cx={size / 2}
            cy={size / 2}
            r={size / 2 - 20}
            fill={Colors.backgroundDark}
          />
        </Svg>

        {/* 可拖动的内圈 */}
        <GestureDetector gesture={panGesture}>
          <Animated.View
            style={[
              styles.innerCircle,
              {
                width: innerSize,
                height: innerSize,
                borderRadius: innerSize / 2,
                transform: [{translateX}, {translateY}],
              },
            ]}
          />
        </GestureDetector>
      </View>
    </GestureHandlerRootView>
  );
};

const styles = StyleSheet.create({
  gestureRoot: {
    flex: 0,
  },
  container: {
    justifyContent: 'center',
    alignItems: 'center',
  },
  svgOverlay: {
    position: 'absolute',
  },
  innerCircle: {
    backgroundColor: Colors.primary,
    ...Shadows.glow,
  },
});

export default Joystick;
