import React, {useState, useEffect, useRef} from 'react';
import {View, StyleSheet, Animated, Easing} from 'react-native';
import {SafeAreaView} from 'react-native-safe-area-context';
import {Text, Button, Card, ProgressBar, IconButton, Surface} from 'react-native-paper';
import Icon from 'react-native-vector-icons/MaterialCommunityIcons';
import Svg, {Path, Circle, Line} from 'react-native-svg';
import {useAppStore} from '../store/appStore';
import {HeartbeatStatus, BATTERY_CONSTANTS} from '../types';
import {Colors, Spacing, BorderRadius, StatusMessages} from '../theme';
import {ConnectionModal} from '../components';

// 心电图动画组件
const ECGAnimation: React.FC<{isConnected: boolean; heartbeat: HeartbeatStatus}> = ({
  isConnected,
  heartbeat,
}) => {
  const animatedValue = useRef(new Animated.Value(0)).current;
  const width = 300;
  const height = 60;

  useEffect(() => {
    const animate = () => {
      animatedValue.setValue(0);
      Animated.timing(animatedValue, {
        toValue: 1,
        duration: heartbeat === HeartbeatStatus.Normal ? 800 : 1200,
        easing: Easing.linear,
        useNativeDriver: true,
      }).start(() => animate());
    };

    if (isConnected && heartbeat !== HeartbeatStatus.Lost) {
      animate();
    }
  }, [isConnected, heartbeat, animatedValue]);

  const getECGPath = () => {
    if (!isConnected || heartbeat === HeartbeatStatus.Lost) {
      return `M 0 ${height / 2} L ${width} ${height / 2}`;
    }
    // ECG波形
    return `M 0 ${height / 2}
            L 50 ${height / 2}
            L 60 ${height / 2 - 5}
            L 70 ${height / 2}
            L 90 ${height / 2}
            L 100 ${height / 2 + 20}
            L 110 ${height / 2 - 30}
            L 120 ${height / 2 + 10}
            L 130 ${height / 2}
            L 200 ${height / 2}
            L ${width} ${height / 2}`;
  };

  const strokeColor = heartbeat === HeartbeatStatus.Normal
    ? Colors.success
    : heartbeat === HeartbeatStatus.Weak
    ? Colors.warning
    : Colors.error;

  return (
    <View style={styles.ecgContainer}>
      <Svg width={width} height={height}>
        <Path
          d={getECGPath()}
          stroke={strokeColor}
          strokeWidth={2}
          fill="none"
          opacity={0.3}
        />
        <Animated.View
          style={{
            transform: [
              {
                translateX: animatedValue.interpolate({
                  inputRange: [0, 1],
                  outputRange: [-width, 0],
                }),
              },
            ],
          }}>
          <Svg width={width} height={height} style={{position: 'absolute'}}>
            <Path
              d={getECGPath()}
              stroke={strokeColor}
              strokeWidth={2}
              fill="none"
            />
          </Svg>
        </Animated.View>
      </Svg>
    </View>
  );
};

// 电池电压显示组件
const BatteryGauge: React.FC<{voltage: number; label: string}> = ({voltage, label}) => {
  const getColor = () => {
    if (voltage >= BATTERY_CONSTANTS.NOMINAL_VOLTAGE) return Colors.batteryFull;
    if (voltage >= BATTERY_CONSTANTS.LOW_VOLTAGE) return Colors.batteryMedium;
    if (voltage >= BATTERY_CONSTANTS.CRITICAL_VOLTAGE) return Colors.batteryLow;
    return Colors.batteryCritical;
  };

  const percentage = Math.max(0, Math.min(1,
    (voltage - BATTERY_CONSTANTS.CUTOFF_VOLTAGE) /
    (BATTERY_CONSTANTS.FULL_VOLTAGE - BATTERY_CONSTANTS.CUTOFF_VOLTAGE)
  ));

  return (
    <View style={styles.batteryGauge}>
      <Text variant="labelSmall" style={styles.batteryLabel}>{label}</Text>
      <View style={styles.batteryBarContainer}>
        <View style={[styles.batteryBar, {width: `${percentage * 100}%`, backgroundColor: getColor()}]} />
      </View>
      <Text variant="bodyMedium" style={[styles.batteryVoltage, {color: getColor()}]}>
        {voltage.toFixed(2)}V
      </Text>
    </View>
  );
};

const DashboardScreen: React.FC = () => {
  const {
    connection,
    systemStatus,
    disconnect,
  } = useAppStore();

  const [showConnectionModal, setShowConnectionModal] = useState(false);

  // 模拟数据（实际从硬件获取）
  const mockSystemStatus = systemStatus || {
    fps: 30,
    cpuTemperature: 45,
    heartbeat: HeartbeatStatus.Normal,
    currentDrawLow: false,
  };

  const mockBattery = connection.battery || {
    voltage1: 3.85,
    voltage2: 3.78,
    percentage: 72,
    isLow: false,
    isCritical: false,
  };

  const handleRevive = () => {
    // 发送电击复苏指令
    console.log('Sending revive command...');
  };

  const getStatusMessage = () => {
    if (!connection.isConnected) return StatusMessages.disconnected;
    if (mockBattery.isCritical) return StatusMessages.criticalBattery;
    if (mockBattery.isLow) return StatusMessages.lowBattery;
    return StatusMessages.connected;
  };

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.content}>
        {/* 标题 */}
        <View style={styles.header}>
          <Text variant="headlineMedium" style={styles.title}>
            意识面板
          </Text>
          <Text variant="bodySmall" style={styles.subtitle}>
            {getStatusMessage()}
          </Text>
        </View>

        {/* 心电图动画 */}
        <Card style={styles.ecgCard}>
          <Card.Content>
            <View style={styles.ecgHeader}>
              <Icon name="heart-pulse" size={24} color={Colors.heartbeat} />
              <Text variant="titleMedium" style={styles.cardTitle}>
                脉冲心跳
              </Text>
            </View>
            <ECGAnimation
              isConnected={connection.isConnected}
              heartbeat={mockSystemStatus.heartbeat}
            />
            {mockSystemStatus.currentDrawLow && (
              <Button
                mode="contained"
                icon="flash"
                buttonColor={Colors.error}
                onPress={handleRevive}
                style={styles.reviveButton}>
                电击复苏
              </Button>
            )}
          </Card.Content>
        </Card>

        {/* 电池监控 */}
        <Card style={styles.card}>
          <Card.Content>
            <View style={styles.cardHeader}>
              <Icon name="battery-charging" size={24} color={Colors.success} />
              <Text variant="titleMedium" style={styles.cardTitle}>
                能量监控
              </Text>
              <Text variant="titleLarge" style={styles.batteryPercentage}>
                {mockBattery.percentage}%
              </Text>
            </View>
            <BatteryGauge voltage={mockBattery.voltage1} label="电池 A" />
            <BatteryGauge voltage={mockBattery.voltage2} label="电池 B" />
            {(mockBattery.isLow || mockBattery.isCritical) && (
              <Surface style={styles.warningBanner}>
                <Icon name="alert" size={20} color={Colors.error} />
                <Text variant="bodySmall" style={styles.warningText}>
                  {mockBattery.isCritical ? '⚠ 电量危急，请立即更换电池！' : '电量不足，请及时更换电池'}
                </Text>
              </Surface>
            )}
          </Card.Content>
        </Card>

        {/* 系统状态 */}
        <Card style={styles.card}>
          <Card.Content>
            <View style={styles.cardHeader}>
              <Icon name="chip" size={24} color={Colors.secondary} />
              <Text variant="titleMedium" style={styles.cardTitle}>
                系统状态
              </Text>
            </View>
            <View style={styles.statsRow}>
              <View style={styles.statItem}>
                <Icon name="speedometer" size={32} color={Colors.primary} />
                <Text variant="headlineSmall" style={styles.statValue}>
                  {mockSystemStatus.fps}
                </Text>
                <Text variant="labelSmall" style={styles.statLabel}>FPS</Text>
              </View>
              <View style={styles.statItem}>
                <Icon name="thermometer" size={32} color={
                  mockSystemStatus.cpuTemperature > 70 ? Colors.error :
                  mockSystemStatus.cpuTemperature > 50 ? Colors.warning : Colors.success
                } />
                <Text variant="headlineSmall" style={styles.statValue}>
                  {mockSystemStatus.cpuTemperature}°
                </Text>
                <Text variant="labelSmall" style={styles.statLabel}>CPU温度</Text>
              </View>
            </View>
          </Card.Content>
        </Card>

        {/* 连接按钮 */}
        <View style={styles.connectionContainer}>
          {!connection.isConnected ? (
            <Button
              mode="contained"
              icon="brain"
              onPress={() => setShowConnectionModal(true)}
              style={styles.connectButton}
              contentStyle={styles.connectButtonContent}>
              建立心智连接
            </Button>
          ) : (
            <Button
              mode="outlined"
              icon="link-variant-off"
              onPress={disconnect}
              style={styles.disconnectButton}
              contentStyle={styles.connectButtonContent}
              textColor={Colors.error}>
              断开心智连接
            </Button>
          )}
        </View>
      </View>

      <ConnectionModal
        visible={showConnectionModal}
        onClose={() => setShowConnectionModal(false)}
      />
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
    marginBottom: Spacing.xl,
  },
  title: {
    color: Colors.primary,
    fontWeight: 'bold',
    textShadowColor: Colors.primaryGlow,
    textShadowRadius: 10,
  },
  subtitle: {
    color: Colors.textSecondary,
    marginTop: Spacing.xs,
  },
  ecgCard: {
    backgroundColor: Colors.backgroundLight,
    marginBottom: Spacing.lg,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  ecgHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: Spacing.md,
  },
  ecgContainer: {
    alignItems: 'center',
    marginVertical: Spacing.sm,
  },
  card: {
    backgroundColor: Colors.backgroundLight,
    marginBottom: Spacing.md,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  cardHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: Spacing.md,
  },
  cardTitle: {
    color: Colors.text,
    marginLeft: Spacing.sm,
    flex: 1,
  },
  batteryPercentage: {
    color: Colors.success,
    fontWeight: 'bold',
  },
  batteryGauge: {
    flexDirection: 'row',
    alignItems: 'center',
    marginVertical: Spacing.xs,
  },
  batteryLabel: {
    color: Colors.textMuted,
    width: 50,
  },
  batteryBarContainer: {
    flex: 1,
    height: 8,
    backgroundColor: Colors.surface,
    borderRadius: 4,
    marginHorizontal: Spacing.sm,
    overflow: 'hidden',
  },
  batteryBar: {
    height: '100%',
    borderRadius: 4,
  },
  batteryVoltage: {
    width: 55,
    textAlign: 'right',
    fontWeight: '600',
  },
  warningBanner: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.errorLight,
    padding: Spacing.sm,
    borderRadius: BorderRadius.sm,
    marginTop: Spacing.md,
  },
  warningText: {
    color: Colors.error,
    marginLeft: Spacing.sm,
    flex: 1,
  },
  statsRow: {
    flexDirection: 'row',
    justifyContent: 'space-around',
  },
  statItem: {
    alignItems: 'center',
    padding: Spacing.md,
  },
  statValue: {
    color: Colors.text,
    fontWeight: 'bold',
    marginTop: Spacing.xs,
  },
  statLabel: {
    color: Colors.textMuted,
  },
  reviveButton: {
    marginTop: Spacing.md,
  },
  connectionContainer: {
    marginTop: 'auto',
    paddingTop: Spacing.lg,
  },
  connectButton: {
    borderRadius: BorderRadius.md,
  },
  disconnectButton: {
    borderRadius: BorderRadius.md,
    borderColor: Colors.error,
  },
  connectButtonContent: {
    paddingVertical: Spacing.xs,
  },
});

export default DashboardScreen;
