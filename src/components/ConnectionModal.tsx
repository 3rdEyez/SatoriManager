import React, {useState} from 'react';
import {View, StyleSheet, FlatList} from 'react-native';
import {
  Modal,
  Portal,
  Text,
  Button,
  IconButton,
  Surface,
  SegmentedButtons,
  ActivityIndicator,
  List,
  Chip,
} from 'react-native-paper';
import {useAppStore} from '../store/appStore';
import {ConnectionType, BluetoothDevice} from '../types';
import {Colors, Spacing, BorderRadius} from '../theme';

interface ConnectionModalProps {
  visible: boolean;
  onClose: () => void;
}

const ConnectionModal: React.FC<ConnectionModalProps> = ({visible, onClose}) => {
  const {
    connection,
    bluetoothScan,
    connectUDP,
    startBluetoothScan,
    stopBluetoothScan,
    connectBluetooth,
    disconnect,
  } = useAppStore();

  const [selectedTab, setSelectedTab] = useState<string>('udp');
  const [connecting, setConnecting] = useState(false);

  const handleUDPConnect = () => {
    connectUDP();
    onClose();
  };

  const handleBluetoothScan = () => {
    startBluetoothScan();
  };

  const handleBluetoothConnect = async (device: BluetoothDevice) => {
    setConnecting(true);
    stopBluetoothScan();
    const success = await connectBluetooth(device.id);
    setConnecting(false);
    if (success) {
      onClose();
    }
  };

  const handleDisconnect = () => {
    disconnect();
    onClose();
  };

  const renderBluetoothDevice = ({item}: {item: BluetoothDevice}) => (
    <List.Item
      title={item.name || '未知设备'}
      description={item.id}
      titleStyle={styles.deviceName}
      descriptionStyle={styles.deviceId}
      style={styles.deviceItem}
      onPress={() => handleBluetoothConnect(item)}
      disabled={connecting}
      right={() => (
        <Chip compact style={styles.rssiChip} textStyle={styles.rssiText}>
          {item.rssi} dBm
        </Chip>
      )}
    />
  );

  return (
    <Portal>
      <Modal
        visible={visible}
        onDismiss={onClose}
        contentContainerStyle={styles.modalContent}>
        {/* 标题栏 */}
        <View style={styles.header}>
          <Text variant="titleLarge" style={styles.title}>
            连接设备
          </Text>
          <IconButton icon="close" iconColor={Colors.text} onPress={onClose} />
        </View>

        {/* 已连接状态 */}
        {connection.isConnected && (
          <Surface style={styles.connectedInfo} elevation={1}>
            <Text variant="bodyMedium" style={styles.connectedText}>
              已连接:{' '}
              {connection.connectionType === ConnectionType.Bluetooth
                ? connection.deviceName || connection.deviceId
                : connection.serverAddress}
            </Text>
            <Button
              mode="contained"
              buttonColor={Colors.error}
              onPress={handleDisconnect}
              style={styles.disconnectButton}>
              断开连接
            </Button>
          </Surface>
        )}

        {/* 标签页切换 */}
        {!connection.isConnected && (
          <>
            <SegmentedButtons
              value={selectedTab}
              onValueChange={setSelectedTab}
              buttons={[
                {value: 'udp', label: 'WiFi (UDP)', icon: 'wifi'},
                {value: 'bluetooth', label: '蓝牙', icon: 'bluetooth'},
              ]}
              style={styles.segmentedButtons}
            />

            {/* UDP 连接 */}
            {selectedTab === 'udp' && (
              <View style={styles.tabContent}>
                <Text variant="bodyMedium" style={styles.description}>
                  通过 WiFi 局域网自动发现并连接 SatoriEye 设备
                </Text>
                <Button
                  mode="contained"
                  icon="magnify"
                  onPress={handleUDPConnect}
                  style={styles.connectButton}>
                  搜索并连接
                </Button>
              </View>
            )}

            {/* 蓝牙连接 */}
            {selectedTab === 'bluetooth' && (
              <View style={styles.tabContent}>
                <Text variant="bodyMedium" style={styles.description}>
                  通过蓝牙连接 SatoriEye 设备
                </Text>

                <Button
                  mode={bluetoothScan.isScanning ? 'outlined' : 'contained'}
                  icon={bluetoothScan.isScanning ? 'stop' : 'bluetooth-connect'}
                  onPress={
                    bluetoothScan.isScanning ? stopBluetoothScan : handleBluetoothScan
                  }
                  style={styles.scanButton}>
                  {bluetoothScan.isScanning ? '停止扫描' : '扫描设备'}
                </Button>

                {/* 扫描状态 */}
                {bluetoothScan.isScanning && (
                  <View style={styles.loadingIndicator}>
                    <ActivityIndicator animating color={Colors.primary} />
                    <Text variant="bodySmall" style={styles.loadingText}>
                      正在扫描...
                    </Text>
                  </View>
                )}

                {/* 错误信息 */}
                {bluetoothScan.error && (
                  <Text variant="bodySmall" style={styles.errorText}>
                    {bluetoothScan.error}
                  </Text>
                )}

                {/* 正在连接 */}
                {connecting && (
                  <View style={styles.loadingIndicator}>
                    <ActivityIndicator animating color={Colors.primary} />
                    <Text variant="bodySmall" style={styles.loadingText}>
                      正在连接...
                    </Text>
                  </View>
                )}

                {/* 设备列表 */}
                <FlatList
                  data={bluetoothScan.devices}
                  keyExtractor={(item) => item.id}
                  renderItem={renderBluetoothDevice}
                  style={styles.deviceList}
                  ListEmptyComponent={
                    !bluetoothScan.isScanning ? (
                      <Text variant="bodySmall" style={styles.emptyText}>
                        点击"扫描设备"搜索附近的 SatoriEye
                      </Text>
                    ) : null
                  }
                />
              </View>
            )}
          </>
        )}
      </Modal>
    </Portal>
  );
};

const styles = StyleSheet.create({
  modalContent: {
    backgroundColor: Colors.background,
    margin: Spacing.xl,
    borderRadius: BorderRadius.lg,
    padding: Spacing.lg,
    maxHeight: '80%',
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: Spacing.md,
  },
  title: {
    color: Colors.text,
    fontWeight: 'bold',
  },
  connectedInfo: {
    backgroundColor: Colors.successLight,
    borderRadius: BorderRadius.md,
    padding: Spacing.lg,
    marginBottom: Spacing.lg,
  },
  connectedText: {
    color: Colors.success,
    marginBottom: Spacing.md,
  },
  disconnectButton: {
    marginTop: Spacing.xs,
  },
  segmentedButtons: {
    marginBottom: Spacing.lg,
  },
  tabContent: {
    flex: 1,
  },
  description: {
    color: Colors.textSecondary,
    textAlign: 'center',
    marginBottom: Spacing.lg,
  },
  connectButton: {
    marginTop: Spacing.sm,
  },
  scanButton: {
    marginBottom: Spacing.md,
  },
  loadingIndicator: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    marginVertical: Spacing.md,
    gap: Spacing.sm,
  },
  loadingText: {
    color: Colors.primary,
  },
  errorText: {
    color: Colors.error,
    textAlign: 'center',
    marginVertical: Spacing.sm,
  },
  deviceList: {
    maxHeight: 250,
  },
  deviceItem: {
    backgroundColor: Colors.surfaceHighlight,
    borderRadius: BorderRadius.md,
    marginBottom: Spacing.sm,
  },
  deviceName: {
    color: Colors.text,
  },
  deviceId: {
    color: Colors.textMuted,
    fontSize: 11,
  },
  rssiChip: {
    backgroundColor: Colors.primaryLight,
  },
  rssiText: {
    color: Colors.primaryDark,
    fontSize: 11,
  },
  emptyText: {
    color: Colors.textMuted,
    textAlign: 'center',
    marginTop: Spacing.xl,
  },
});

export default ConnectionModal;
