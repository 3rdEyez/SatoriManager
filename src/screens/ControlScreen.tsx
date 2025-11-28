import React from 'react';
import {View, StyleSheet} from 'react-native';
import {SafeAreaView} from 'react-native-safe-area-context';
import {GestureHandlerRootView} from 'react-native-gesture-handler';
import {Text, Surface, Card} from 'react-native-paper';
import {Dial} from '../components';
import {useAppStore} from '../store/appStore';
import {Colors, Spacing} from '../theme';

const ControlScreen: React.FC = () => {
  const {
    connection,
    eyelidPosition,
    pupilSize,
    setEyelidPosition,
    setPupilSize,
  } = useAppStore();

  return (
    <SafeAreaView style={styles.container}>
      <GestureHandlerRootView style={styles.gestureRoot}>
        <View style={styles.content}>
          <Text variant="headlineSmall" style={styles.title}>
            眼部控制
          </Text>

          <View style={styles.dialContainer}>
            {/* 眼皮控制 */}
            <Card style={styles.dialCard}>
              <Card.Content style={styles.dialContent}>
                <Dial
                  size={130}
                  value={eyelidPosition}
                  onChange={setEyelidPosition}
                  label="眼皮角度"
                  disabled={!connection.isConnected}
                />
              </Card.Content>
            </Card>

            {/* 瞳孔控制（预留） */}
            <Card style={styles.dialCard}>
              <Card.Content style={styles.dialContent}>
                <Dial
                  size={130}
                  value={pupilSize}
                  onChange={setPupilSize}
                  label="瞳孔大小"
                  disabled={true}
                />
                <Text variant="labelSmall" style={styles.comingSoon}>
                  即将推出
                </Text>
              </Card.Content>
            </Card>
          </View>

          {!connection.isConnected && (
            <Surface style={styles.disconnectedOverlay} elevation={0}>
              <Text variant="titleMedium" style={styles.disconnectedText}>
                请先连接设备
              </Text>
            </Surface>
          )}
        </View>
      </GestureHandlerRootView>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.background,
  },
  gestureRoot: {
    flex: 1,
  },
  content: {
    flex: 1,
    padding: Spacing.xl,
  },
  title: {
    color: Colors.text,
    fontWeight: 'bold',
    marginBottom: Spacing.xxxl,
    textAlign: 'center',
  },
  dialContainer: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    flex: 1,
    alignItems: 'center',
    gap: Spacing.lg,
  },
  dialCard: {
    backgroundColor: Colors.backgroundLight,
    borderRadius: 16,
    flex: 1,
  },
  dialContent: {
    alignItems: 'center',
    paddingVertical: Spacing.xl,
  },
  comingSoon: {
    color: Colors.textMuted,
    marginTop: Spacing.sm,
  },
  disconnectedOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: Colors.overlay,
    justifyContent: 'center',
    alignItems: 'center',
  },
  disconnectedText: {
    color: Colors.text,
  },
});

export default ControlScreen;
