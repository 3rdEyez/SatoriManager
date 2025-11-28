import React, {useState} from 'react';
import {View, StyleSheet, ScrollView} from 'react-native';
import {SafeAreaView} from 'react-native-safe-area-context';
import {Text, Button, Card, Divider, Switch} from 'react-native-paper';
import Slider from '@react-native-community/slider';
import Icon from 'react-native-vector-icons/MaterialCommunityIcons';
import {useAppStore} from '../store/appStore';
import {PID_DEFAULTS, FILTER_DEFAULTS} from '../types';
import {Colors, Spacing, BorderRadius, StatusMessages} from '../theme';

// 参数滑块组件
const ParameterSlider: React.FC<{
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  unit?: string;
  description?: string;
  onChange: (value: number) => void;
  color?: string;
}> = ({label, value, min, max, step, unit = '', description, onChange, color = Colors.primary}) => {
  return (
    <View style={styles.sliderContainer}>
      <View style={styles.sliderHeader}>
        <Text variant="titleSmall" style={styles.sliderLabel}>{label}</Text>
        <Text variant="titleMedium" style={[styles.sliderValue, {color}]}>
          {value.toFixed(step < 1 ? 2 : 0)}{unit}
        </Text>
      </View>
      <Slider
        style={styles.slider}
        minimumValue={min}
        maximumValue={max}
        step={step}
        value={value}
        onValueChange={onChange}
        minimumTrackTintColor={color}
        maximumTrackTintColor={Colors.border}
        thumbTintColor={color}
      />
      {description && (
        <Text variant="bodySmall" style={styles.sliderDescription}>
          {description}
        </Text>
      )}
    </View>
  );
};

const TuningLabScreen: React.FC = () => {
  const {connection} = useAppStore();

  // PID 参数
  const [pidP, setPidP] = useState(PID_DEFAULTS.p);
  const [pidI, setPidI] = useState(PID_DEFAULTS.i);
  const [pidD, setPidD] = useState(PID_DEFAULTS.d);

  // 滤波器参数
  const [kalmanR, setKalmanR] = useState(FILTER_DEFAULTS.kalmanR);

  // 校准状态
  const [isCalibrated, setIsCalibrated] = useState(false);

  // 实时预览
  const [livePreview, setLivePreview] = useState(true);

  const handleApplyPID = () => {
    console.log('Applying PID:', {p: pidP, i: pidI, d: pidD});
    // 发送 PID 参数到硬件
  };

  const handleApplyFilter = () => {
    console.log('Applying Filter:', {kalmanR});
    // 发送滤波器参数到硬件
  };

  const handleCalibrate = () => {
    console.log('Calibrating center position...');
    setIsCalibrated(true);
    // 发送校准指令
  };

  const handleResetPID = () => {
    setPidP(PID_DEFAULTS.p);
    setPidI(PID_DEFAULTS.i);
    setPidD(PID_DEFAULTS.d);
  };

  const handleResetFilter = () => {
    setKalmanR(FILTER_DEFAULTS.kalmanR);
  };

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView style={styles.scrollView} contentContainerStyle={styles.content}>
        {/* 标题 */}
        <View style={styles.header}>
          <Text variant="headlineMedium" style={styles.title}>
            潜意识调优
          </Text>
          <Text variant="bodySmall" style={styles.subtitle}>
            Tuning Lab - Engineering Mode
          </Text>
        </View>

        {/* 实时预览开关 */}
        <View style={styles.previewToggle}>
          <Icon name="eye-check" size={20} color={Colors.secondary} />
          <Text variant="bodyMedium" style={styles.previewLabel}>
            实时预览
          </Text>
          <Switch
            value={livePreview}
            onValueChange={setLivePreview}
            color={Colors.secondary}
          />
        </View>

        {/* PID 参数调整 */}
        <Card style={styles.card}>
          <Card.Content>
            <View style={styles.cardHeader}>
              <Icon name="tune" size={24} color={Colors.primary} />
              <Text variant="titleMedium" style={styles.cardTitle}>
                PID 参数整定
              </Text>
              <Button
                mode="text"
                compact
                onPress={handleResetPID}
                textColor={Colors.textMuted}>
                重置
              </Button>
            </View>

            <ParameterSlider
              label="P (比例)"
              value={pidP}
              min={0}
              max={10}
              step={0.1}
              onChange={setPidP}
              description="增大可加快响应速度，过大会导致振荡"
              color={Colors.error}
            />

            <ParameterSlider
              label="I (积分)"
              value={pidI}
              min={0}
              max={1}
              step={0.01}
              onChange={setPidI}
              description="消除稳态误差，过大会导致超调"
              color={Colors.success}
            />

            <ParameterSlider
              label="D (微分)"
              value={pidD}
              min={0}
              max={1}
              step={0.01}
              onChange={setPidD}
              description="抑制振荡，增加系统稳定性"
              color={Colors.secondary}
            />

            <Button
              mode="contained"
              icon="check"
              onPress={handleApplyPID}
              disabled={!connection.isConnected}
              style={styles.applyButton}>
              应用 PID 参数
            </Button>
          </Card.Content>
        </Card>

        {/* 滤波器参数 */}
        <Card style={styles.card}>
          <Card.Content>
            <View style={styles.cardHeader}>
              <Icon name="filter" size={24} color={Colors.warning} />
              <Text variant="titleMedium" style={styles.cardTitle}>
                卡尔曼滤波
              </Text>
              <Button
                mode="text"
                compact
                onPress={handleResetFilter}
                textColor={Colors.textMuted}>
                重置
              </Button>
            </View>

            <ParameterSlider
              label="观测噪声 R"
              value={kalmanR}
              min={0.01}
              max={10}
              step={0.01}
              onChange={setKalmanR}
              description="越大越平滑但延迟高，越小响应快但噪声大"
              color={Colors.warning}
            />

            <View style={styles.filterPreview}>
              <Text variant="labelSmall" style={styles.filterLabel}>
                平滑度预览:
              </Text>
              <View style={styles.filterBar}>
                <View style={styles.filterIndicator}>
                  <Text variant="labelSmall" style={styles.filterText}>抖动</Text>
                </View>
                <View
                  style={[
                    styles.filterMarker,
                    {left: `${Math.min(100, (kalmanR / 10) * 100)}%`},
                  ]}
                />
                <View style={styles.filterIndicator}>
                  <Text variant="labelSmall" style={styles.filterText}>平滑</Text>
                </View>
              </View>
            </View>

            <Button
              mode="contained"
              icon="check"
              onPress={handleApplyFilter}
              disabled={!connection.isConnected}
              style={styles.applyButton}
              buttonColor={Colors.warning}>
              应用滤波参数
            </Button>
          </Card.Content>
        </Card>

        {/* 视觉校准 */}
        <Card style={styles.card}>
          <Card.Content>
            <View style={styles.cardHeader}>
              <Icon name="crosshairs-gps" size={24} color={Colors.secondary} />
              <Text variant="titleMedium" style={styles.cardTitle}>
                视觉校准
              </Text>
            </View>

            <Text variant="bodyMedium" style={styles.calibrationDescription}>
              将眼球移动到正前方位置，然后点击校准按钮设置为(0,0)原点。
              这可以修正组装时的机械偏差。
            </Text>

            <View style={styles.calibrationStatus}>
              <Icon
                name={isCalibrated ? 'check-circle' : 'alert-circle'}
                size={20}
                color={isCalibrated ? Colors.success : Colors.warning}
              />
              <Text
                variant="bodySmall"
                style={[
                  styles.calibrationStatusText,
                  {color: isCalibrated ? Colors.success : Colors.warning},
                ]}>
                {isCalibrated ? '已校准' : '未校准'}
              </Text>
            </View>

            <Button
              mode="contained"
              icon="crosshairs"
              onPress={handleCalibrate}
              disabled={!connection.isConnected}
              style={styles.calibrateButton}
              buttonColor={Colors.secondary}>
              中心校准
            </Button>
          </Card.Content>
        </Card>

        {/* 连接状态提示 */}
        {!connection.isConnected && (
          <View style={styles.disconnectedBanner}>
            <Icon name="link-variant-off" size={20} color={Colors.error} />
            <Text variant="bodySmall" style={styles.disconnectedText}>
              {StatusMessages.disconnected} - 请先建立心智连接
            </Text>
          </View>
        )}

        {/* 版本信息 */}
        <View style={styles.footer}>
          <Text variant="bodySmall" style={styles.versionText}>
            SatoriManager v2.0.0
          </Text>
          <Text variant="labelSmall" style={styles.versionSubtext}>
            Satori Theme Edition
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
    padding: Spacing.lg,
    paddingBottom: Spacing.xxxl,
  },
  header: {
    alignItems: 'center',
    marginBottom: Spacing.xl,
  },
  title: {
    color: Colors.warning,
    fontWeight: 'bold',
    textShadowColor: Colors.warningLight,
    textShadowRadius: 10,
  },
  subtitle: {
    color: Colors.textMuted,
    marginTop: Spacing.xs,
  },
  previewToggle: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: Spacing.lg,
    gap: Spacing.sm,
  },
  previewLabel: {
    color: Colors.textSecondary,
    flex: 1,
  },
  card: {
    backgroundColor: Colors.backgroundLight,
    marginBottom: Spacing.lg,
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
  sliderContainer: {
    marginBottom: Spacing.lg,
  },
  sliderHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: Spacing.xs,
  },
  sliderLabel: {
    color: Colors.text,
  },
  sliderValue: {
    fontWeight: 'bold',
  },
  slider: {
    width: '100%',
    height: 40,
  },
  sliderDescription: {
    color: Colors.textMuted,
    marginTop: Spacing.xs,
  },
  applyButton: {
    marginTop: Spacing.sm,
    borderRadius: BorderRadius.md,
  },
  filterPreview: {
    marginTop: Spacing.md,
    marginBottom: Spacing.md,
  },
  filterLabel: {
    color: Colors.textMuted,
    marginBottom: Spacing.xs,
  },
  filterBar: {
    height: 24,
    backgroundColor: Colors.surface,
    borderRadius: BorderRadius.sm,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: Spacing.sm,
    position: 'relative',
  },
  filterIndicator: {
    flex: 1,
  },
  filterText: {
    color: Colors.textMuted,
    fontSize: 10,
  },
  filterMarker: {
    position: 'absolute',
    width: 4,
    height: 20,
    backgroundColor: Colors.warning,
    borderRadius: 2,
    top: 2,
  },
  calibrationDescription: {
    color: Colors.textSecondary,
    marginBottom: Spacing.md,
    lineHeight: 20,
  },
  calibrationStatus: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: Spacing.md,
    gap: Spacing.xs,
  },
  calibrationStatusText: {
    fontWeight: '500',
  },
  calibrateButton: {
    borderRadius: BorderRadius.md,
  },
  disconnectedBanner: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.errorLight,
    padding: Spacing.md,
    borderRadius: BorderRadius.md,
    marginBottom: Spacing.lg,
    gap: Spacing.sm,
  },
  disconnectedText: {
    color: Colors.error,
  },
  footer: {
    alignItems: 'center',
    marginTop: Spacing.xl,
  },
  versionText: {
    color: Colors.textMuted,
  },
  versionSubtext: {
    color: Colors.textDisabled,
    marginTop: Spacing.xs,
  },
});

export default TuningLabScreen;
