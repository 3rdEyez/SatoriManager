import React from 'react';
import {View, StyleSheet, ScrollView} from 'react-native';
import {SafeAreaView} from 'react-native-safe-area-context';
import {Text, Switch, Divider, List, useTheme} from 'react-native-paper';
import Slider from '@react-native-community/slider';
import {useAppStore} from '../store/appStore';
import {Colors, Spacing} from '../theme';

const SettingScreen: React.FC = () => {
  const theme = useTheme();
  const {settings, setSettings} = useAppStore();

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView style={styles.scrollView} contentContainerStyle={styles.content}>
        <Text variant="headlineSmall" style={styles.title}>
          设置
        </Text>

        {/* PWM 范围设置 */}
        <View style={styles.settingSection}>
          <View style={styles.settingHeader}>
            <Text variant="titleMedium" style={styles.settingLabel}>
              PWM 变化范围
            </Text>
            <Text variant="titleMedium" style={styles.settingValue}>
              ±{settings.pwmRange}
            </Text>
          </View>
          <Slider
            style={styles.slider}
            minimumValue={0}
            maximumValue={500}
            step={10}
            value={settings.pwmRange}
            onValueChange={(value) => setSettings({pwmRange: value})}
            minimumTrackTintColor={Colors.primary}
            maximumTrackTintColor={Colors.border}
            thumbTintColor={Colors.primary}
          />
          <Text variant="bodySmall" style={styles.settingHint}>
            控制自动模式下眼球运动的幅度
          </Text>
        </View>

        <Divider style={styles.divider} />

        {/* 更新间隔设置 */}
        <View style={styles.settingSection}>
          <View style={styles.settingHeader}>
            <Text variant="titleMedium" style={styles.settingLabel}>
              更新间隔
            </Text>
            <Text variant="titleMedium" style={styles.settingValue}>
              {settings.updateInterval}ms
            </Text>
          </View>
          <Slider
            style={styles.slider}
            minimumValue={100}
            maximumValue={5000}
            step={100}
            value={settings.updateInterval}
            onValueChange={(value) => setSettings({updateInterval: value})}
            minimumTrackTintColor={Colors.primary}
            maximumTrackTintColor={Colors.border}
            thumbTintColor={Colors.primary}
          />
          <Text variant="bodySmall" style={styles.settingHint}>
            控制自动模式下 PWM 更新的频率
          </Text>
        </View>

        <Divider style={styles.divider} />

        {/* 开关设置 */}
        <List.Item
          title="松开自动复位"
          description="摇杆释放时自动回到中心位置"
          titleStyle={styles.listTitle}
          descriptionStyle={styles.listDescription}
          right={() => (
            <Switch
              value={settings.resetStickOnRelease}
              onValueChange={(value) => setSettings({resetStickOnRelease: value})}
              color={Colors.primary}
            />
          )}
        />

        <List.Item
          title="启用自动眨眼"
          description="定时自动执行眨眼动作"
          titleStyle={styles.listTitle}
          descriptionStyle={styles.listDescription}
          right={() => (
            <Switch
              value={settings.autoWinkEnabled}
              onValueChange={(value) => setSettings({autoWinkEnabled: value})}
              color={Colors.primary}
            />
          )}
        />

        {/* 版本信息 */}
        <View style={styles.footer}>
          <Text variant="bodyMedium" style={styles.versionText}>
            SatoriManager v1.0.0
          </Text>
          <Text variant="bodySmall" style={styles.versionHint}>
            React Native 跨平台版本
          </Text>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.background,
  },
  scrollView: {
    flex: 1,
  },
  content: {
    padding: Spacing.xl,
    paddingBottom: Spacing.xxxl,
  },
  title: {
    color: Colors.text,
    fontWeight: 'bold',
    marginBottom: Spacing.xxl,
  },
  settingSection: {
    marginBottom: Spacing.lg,
  },
  settingHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: Spacing.sm,
  },
  settingLabel: {
    color: Colors.text,
  },
  settingValue: {
    color: Colors.primary,
    fontWeight: '600',
  },
  slider: {
    width: '100%',
    height: 40,
  },
  settingHint: {
    color: Colors.textMuted,
    marginTop: Spacing.xs,
  },
  divider: {
    backgroundColor: Colors.border,
    marginVertical: Spacing.lg,
  },
  listTitle: {
    color: Colors.text,
  },
  listDescription: {
    color: Colors.textMuted,
  },
  footer: {
    marginTop: Spacing.xxxl,
    alignItems: 'center',
  },
  versionText: {
    color: Colors.textMuted,
  },
  versionHint: {
    color: Colors.textDisabled,
    marginTop: Spacing.xs,
  },
});

export default SettingScreen;
