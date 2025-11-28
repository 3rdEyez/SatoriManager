import React, {useCallback, useState} from 'react';
import {View, StyleSheet} from 'react-native';
import {SafeAreaView} from 'react-native-safe-area-context';
import {Button, Text, Chip, Surface, useTheme} from 'react-native-paper';
import Icon from 'react-native-vector-icons/MaterialCommunityIcons';
import {Joystick, ConnectionModal} from '../components';
import {useAppStore} from '../store/appStore';
import {EyeMode, ConnectionType} from '../types';
import {Colors, Spacing} from '../theme';

const MainScreen: React.FC = () => {
  const theme = useTheme();
  const {
    connection,
    currentMode,
    battery,
    settings,
    actionNames,
    disconnect,
    switchMode,
    executeAction,
    setJoystickPosition,
  } = useAppStore();

  const [showConnectionModal, setShowConnectionModal] = useState(false);

  const handleJoystickMove = useCallback(
    (x: number, y: number) => {
      setJoystickPosition({x, y});
    },
    [setJoystickPosition],
  );

  const modeButtons = [
    {mode: EyeMode.Auto, label: '自动', icon: 'play-circle'},
    {mode: EyeMode.Manual, label: '手动', icon: 'gesture-tap'},
    {mode: EyeMode.Sleep, label: '睡眠', icon: 'sleep'},
    {mode: EyeMode.FacialRecognition, label: '追踪', icon: 'face-recognition'},
  ];

  const getConnectionStatusText = () => {
    if (!connection.isConnected) return null;
    if (connection.connectionType === ConnectionType.Bluetooth) {
      return `蓝牙: ${connection.deviceName || '已连接'}`;
    } else if (connection.connectionType === ConnectionType.UDP) {
      return `WiFi: ${connection.serverAddress}`;
    }
    return '已连接';
  };

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.content}>
        {/* 连接状态指示 */}
        {connection.isConnected && (
          <Surface style={styles.statusBar} elevation={1}>
            <Icon name="check-circle" size={16} color={Colors.success} />
            <Text variant="bodySmall" style={styles.statusText}>
              {getConnectionStatusText()}
            </Text>
            <Chip
              icon="battery"
              compact
              textStyle={styles.batteryChipText}
              style={styles.batteryChip}>
              {battery}%
            </Chip>
          </Surface>
        )}

        {/* 模式切换区域 */}
        <View style={styles.modeContainer}>
          <Text variant="titleSmall" style={styles.sectionTitle}>
            模式选择
          </Text>
          <View style={styles.modeButtons}>
            {modeButtons.map(({mode, label, icon}) => (
              <Button
                key={mode}
                mode={currentMode === mode ? 'contained' : 'outlined'}
                icon={icon}
                onPress={() => switchMode(mode)}
                disabled={!connection.isConnected}
                compact
                style={styles.modeButton}
                labelStyle={styles.modeButtonLabel}>
                {label}
              </Button>
            ))}
          </View>
        </View>

        {/* 预设动作区域 */}
        <View style={styles.actionContainer}>
          <Text variant="titleSmall" style={styles.sectionTitle}>
            预设动作
          </Text>
          <View style={styles.actionButtons}>
            {actionNames.map((name) => (
              <Button
                key={name}
                mode="elevated"
                icon="animation-play"
                onPress={() => executeAction(name)}
                disabled={!connection.isConnected}
                compact
                style={styles.actionButton}
                labelStyle={styles.actionButtonLabel}>
                {name}
              </Button>
            ))}
          </View>
        </View>

        {/* 摇杆区域 */}
        <View style={styles.joystickContainer}>
          <Joystick
            size={200}
            innerSize={65}
            battery={battery}
            resetOnRelease={settings.resetStickOnRelease}
            onMove={handleJoystickMove}
          />
        </View>

        {/* 连接按钮 */}
        <View style={styles.connectionContainer}>
          {!connection.isConnected ? (
            <Button
              mode="contained"
              icon="wifi"
              onPress={() => setShowConnectionModal(true)}
              style={styles.connectButton}
              contentStyle={styles.connectButtonContent}>
              连接设备
            </Button>
          ) : (
            <Button
              mode="outlined"
              icon="wifi-off"
              onPress={disconnect}
              style={styles.disconnectButton}
              contentStyle={styles.connectButtonContent}
              textColor={Colors.error}>
              断开连接
            </Button>
          )}
        </View>
      </View>

      {/* 连接模态框 */}
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
  statusBar: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.successLight,
    borderRadius: 12,
    paddingHorizontal: Spacing.md,
    paddingVertical: Spacing.sm,
    marginBottom: Spacing.md,
    gap: Spacing.sm,
  },
  statusText: {
    flex: 1,
    color: Colors.success,
  },
  batteryChip: {
    backgroundColor: 'transparent',
    height: 28,
  },
  batteryChipText: {
    color: Colors.success,
    fontSize: 12,
  },
  sectionTitle: {
    color: Colors.textSecondary,
    marginBottom: Spacing.sm,
  },
  modeContainer: {
    marginBottom: Spacing.lg,
  },
  modeButtons: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: Spacing.sm,
  },
  modeButton: {
    flex: 1,
    minWidth: '45%',
  },
  modeButtonLabel: {
    fontSize: 13,
  },
  actionContainer: {
    marginBottom: Spacing.lg,
  },
  actionButtons: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: Spacing.sm,
  },
  actionButton: {
    minWidth: 100,
  },
  actionButtonLabel: {
    fontSize: 13,
  },
  joystickContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  connectionContainer: {
    paddingVertical: Spacing.md,
  },
  connectButton: {
    borderRadius: 12,
  },
  disconnectButton: {
    borderRadius: 12,
    borderColor: Colors.error,
  },
  connectButtonContent: {
    paddingVertical: Spacing.xs,
  },
});

export default MainScreen;
