import React, {useCallback, useRef} from 'react';
import {View, StyleSheet} from 'react-native';
import {Text} from 'react-native-paper';
import {Gesture, GestureDetector} from 'react-native-gesture-handler';
import Svg, {Circle, Line} from 'react-native-svg';
import {Colors, Spacing} from '../theme';

interface DialProps {
  size?: number;
  value: number; // 0-1
  onChange: (value: number) => void;
  label?: string;
  disabled?: boolean;
}

const Dial: React.FC<DialProps> = ({
  size = 120,
  value,
  onChange,
  label,
  disabled = false,
}) => {
  const lastAngle = useRef(0);
  const centerX = size / 2;
  const centerY = size / 2;
  const radius = size / 2 - 10;

  // 将值转换为角度 (0-1 -> -135° to 135°)
  const valueToAngle = useCallback((v: number) => {
    return -135 + v * 270;
  }, []);

  // 将角度转换为值
  const angleToValue = useCallback((angle: number) => {
    const normalized = ((angle + 135) % 360 + 360) % 360;
    return Math.max(0, Math.min(1, normalized / 270));
  }, []);

  // 计算指示器位置
  const indicatorAngle = valueToAngle(value);
  const indicatorRad = (indicatorAngle * Math.PI) / 180;
  const indicatorX = centerX + (radius - 15) * Math.cos(indicatorRad);
  const indicatorY = centerY + (radius - 15) * Math.sin(indicatorRad);

  const panGesture = Gesture.Pan()
    .enabled(!disabled)
    .onStart((event) => {
      const dx = event.x - centerX;
      const dy = event.y - centerY;
      lastAngle.current = Math.atan2(dy, dx) * (180 / Math.PI);
    })
    .onUpdate((event) => {
      const dx = event.x - centerX;
      const dy = event.y - centerY;
      const currentAngle = Math.atan2(dy, dx) * (180 / Math.PI);
      const deltaAngle = currentAngle - lastAngle.current;

      // 处理角度跨越 180/-180 的情况
      let adjustedDelta = deltaAngle;
      if (deltaAngle > 180) adjustedDelta -= 360;
      if (deltaAngle < -180) adjustedDelta += 360;

      const newValue = value + adjustedDelta / 270;
      onChange(Math.max(0, Math.min(1, newValue)));
      lastAngle.current = currentAngle;
    });

  return (
    <View style={[styles.container, {width: size, height: size + 50}]}>
      <GestureDetector gesture={panGesture}>
        <View style={[styles.dialContainer, {width: size, height: size}]}>
          <Svg width={size} height={size}>
            {/* 背景圆环 */}
            <Circle
              cx={centerX}
              cy={centerY}
              r={radius}
              fill={Colors.backgroundDark}
              stroke={Colors.glow}
              strokeWidth={3}
            />
            {/* 刻度线 */}
            {Array.from({length: 11}).map((_, i) => {
              const angle = -135 + i * 27;
              const rad = (angle * Math.PI) / 180;
              const x1 = centerX + (radius - 5) * Math.cos(rad);
              const y1 = centerY + (radius - 5) * Math.sin(rad);
              const x2 = centerX + (radius - 15) * Math.cos(rad);
              const y2 = centerY + (radius - 15) * Math.sin(rad);
              return (
                <Line
                  key={i}
                  x1={x1}
                  y1={y1}
                  x2={x2}
                  y2={y2}
                  stroke={Colors.borderLight}
                  strokeWidth={2}
                />
              );
            })}
            {/* 指示器 */}
            <Circle
              cx={indicatorX}
              cy={indicatorY}
              r={8}
              fill={Colors.primary}
            />
            {/* 中心点 */}
            <Circle
              cx={centerX}
              cy={centerY}
              r={10}
              fill={Colors.primary}
            />
          </Svg>
        </View>
      </GestureDetector>
      {label && (
        <Text variant="bodyMedium" style={styles.label}>
          {label}
        </Text>
      )}
      <Text variant="bodySmall" style={styles.valueText}>
        {Math.round(value * 100)}%
      </Text>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    alignItems: 'center',
  },
  dialContainer: {
    justifyContent: 'center',
    alignItems: 'center',
  },
  label: {
    color: Colors.text,
    fontWeight: '500',
    marginTop: Spacing.sm,
  },
  valueText: {
    color: Colors.textSecondary,
    marginTop: Spacing.xs,
  },
});

export default Dial;
