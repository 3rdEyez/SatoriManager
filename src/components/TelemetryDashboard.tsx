import React, {useEffect, useState, useRef} from 'react';
import {View, StyleSheet, ScrollView} from 'react-native';
import {Surface, Text, IconButton, Divider} from 'react-native-paper';
import {PerformanceMonitor, PerformanceStats} from '../utils/PerformanceMonitor';
import {theme} from '../theme';

/**
 * 遥测仪表盘属性
 */
interface TelemetryDashboardProps {
  performanceMonitor: PerformanceMonitor;
  videoStreamStats?: {
    currentFPS: number;
    droppedFrames: number;
    avgLatency: number;
  };
  faceDetectionStats?: {
    avgFPS: number;
    avgLatency: number;
    faceCount: number;
  };
  visualServoStats?: {
    errorX: number;
    errorY: number;
    outputX: number;
    outputY: number;
  };
  style?: any;
}

/**
 * 遥测仪表盘组件
 * 显示实时性能指标
 */
export const TelemetryDashboard: React.FC<TelemetryDashboardProps> = ({
  performanceMonitor,
  videoStreamStats,
  faceDetectionStats,
  visualServoStats,
  style,
}) => {
  const [stats, setStats] = useState<PerformanceStats>(performanceMonitor.getStats());
  const [isExpanded, setIsExpanded] = useState(true);
  const updateIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // 定期更新统计信息
  useEffect(() => {
    updateIntervalRef.current = setInterval(() => {
      setStats(performanceMonitor.getStats());
    }, 500);

    return () => {
      if (updateIntervalRef.current) {
        clearInterval(updateIntervalRef.current);
      }
    };
  }, [performanceMonitor]);

  const MetricItem: React.FC<{
    label: string;
    value: string | number;
    unit?: string;
    warning?: boolean;
    error?: boolean;
  }> = ({label, value, unit, warning, error}) => {
    let valueColor = theme.colors.text;
    if (error) {
      valueColor = theme.colors.error;
    } else if (warning) {
      valueColor = theme.colors.warning;
    }

    return (
      <View style={styles.metricItem}>
        <Text style={styles.metricLabel}>{label}</Text>
        <View style={styles.metricValueContainer}>
          <Text style={[styles.metricValue, {color: valueColor}]}>
            {typeof value === 'number' ? value.toFixed(1) : value}
          </Text>
          {unit && <Text style={styles.metricUnit}>{unit}</Text>}
        </View>
      </View>
    );
  };

  return (
    <Surface style={[styles.container, style]} elevation={2}>
      {/* 标题栏 */}
      <View style={styles.header}>
        <View style={styles.headerLeft}>
          <IconButton icon="chart-line" size={20} iconColor={theme.colors.primary} />
          <Text style={styles.title}>性能监控</Text>
        </View>
        <IconButton
          icon={isExpanded ? 'chevron-up' : 'chevron-down'}
          size={20}
          onPress={() => setIsExpanded(!isExpanded)}
        />
      </View>

      {isExpanded && (
        <ScrollView style={styles.content} showsVerticalScrollIndicator={false}>
          {/* 总体性能 */}
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>总体性能</Text>
            <View style={styles.metricsGrid}>
              <MetricItem
                label="帧率"
                value={stats.fps}
                unit="FPS"
                warning={stats.fps < 45}
                error={stats.fps < 30}
              />
              <MetricItem
                label="平均延迟"
                value={stats.avgLatency}
                unit="ms"
                warning={stats.avgLatency > 100}
                error={stats.avgLatency > 150}
              />
              <MetricItem
                label="P95 延迟"
                value={stats.p95Latency}
                unit="ms"
                warning={stats.p95Latency > 120}
                error={stats.p95Latency > 180}
              />
              <MetricItem
                label="P99 延迟"
                value={stats.p99Latency}
                unit="ms"
                warning={stats.p99Latency > 150}
                error={stats.p99Latency > 200}
              />
            </View>
          </View>

          <Divider style={styles.divider} />

          {/* 视频流统计 */}
          {videoStreamStats && (
            <>
              <View style={styles.section}>
                <Text style={styles.sectionTitle}>视频流</Text>
                <View style={styles.metricsGrid}>
                  <MetricItem
                    label="视频 FPS"
                    value={videoStreamStats.currentFPS}
                    unit="FPS"
                    warning={videoStreamStats.currentFPS < 20}
                    error={videoStreamStats.currentFPS < 15}
                  />
                  <MetricItem
                    label="丢帧数"
                    value={videoStreamStats.droppedFrames}
                    unit="帧"
                    warning={videoStreamStats.droppedFrames > 10}
                    error={videoStreamStats.droppedFrames > 50}
                  />
                  <MetricItem
                    label="视频延迟"
                    value={videoStreamStats.avgLatency}
                    unit="ms"
                    warning={videoStreamStats.avgLatency > 80}
                    error={videoStreamStats.avgLatency > 120}
                  />
                  <MetricItem
                    label="总帧数"
                    value={stats.frameCount}
                    unit="帧"
                  />
                </View>
              </View>
              <Divider style={styles.divider} />
            </>
          )}

          {/* 人脸检测统计 */}
          {faceDetectionStats && (
            <>
              <View style={styles.section}>
                <Text style={styles.sectionTitle}>人脸检测</Text>
                <View style={styles.metricsGrid}>
                  <MetricItem
                    label="检测 FPS"
                    value={faceDetectionStats.avgFPS}
                    unit="FPS"
                    warning={faceDetectionStats.avgFPS < 15}
                    error={faceDetectionStats.avgFPS < 10}
                  />
                  <MetricItem
                    label="检测延迟"
                    value={faceDetectionStats.avgLatency}
                    unit="ms"
                    warning={faceDetectionStats.avgLatency > 50}
                    error={faceDetectionStats.avgLatency > 80}
                  />
                  <MetricItem
                    label="检测到人脸"
                    value={faceDetectionStats.faceCount}
                    unit="个"
                  />
                </View>
              </View>
              <Divider style={styles.divider} />
            </>
          )}

          {/* 视觉伺服统计 */}
          {visualServoStats && (
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>视觉伺服</Text>
              <View style={styles.metricsGrid}>
                <MetricItem
                  label="误差 X"
                  value={visualServoStats.errorX}
                  unit=""
                  warning={Math.abs(visualServoStats.errorX) > 0.3}
                  error={Math.abs(visualServoStats.errorX) > 0.5}
                />
                <MetricItem
                  label="误差 Y"
                  value={visualServoStats.errorY}
                  unit=""
                  warning={Math.abs(visualServoStats.errorY) > 0.3}
                  error={Math.abs(visualServoStats.errorY) > 0.5}
                />
                <MetricItem
                  label="输出 X"
                  value={visualServoStats.outputX}
                  unit="PWM"
                />
                <MetricItem
                  label="输出 Y"
                  value={visualServoStats.outputY}
                  unit="PWM"
                />
              </View>
            </View>
          )}

          {/* 延迟分布 */}
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>延迟分布</Text>
            <View style={styles.latencyDistribution}>
              <LatencyBar
                label="Min"
                value={stats.minLatency}
                maxValue={stats.maxLatency}
                color={theme.colors.success}
              />
              <LatencyBar
                label="P50"
                value={stats.p50Latency}
                maxValue={stats.maxLatency}
                color={theme.colors.primary}
              />
              <LatencyBar
                label="Avg"
                value={stats.avgLatency}
                maxValue={stats.maxLatency}
                color={theme.colors.secondary}
              />
              <LatencyBar
                label="P95"
                value={stats.p95Latency}
                maxValue={stats.maxLatency}
                color={theme.colors.warning}
              />
              <LatencyBar
                label="P99"
                value={stats.p99Latency}
                maxValue={stats.maxLatency}
                color={theme.colors.warning}
              />
              <LatencyBar
                label="Max"
                value={stats.maxLatency}
                maxValue={stats.maxLatency}
                color={theme.colors.error}
              />
            </View>
          </View>

          {/* 丢帧率 */}
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>丢帧统计</Text>
            <View style={styles.dropRateContainer}>
              <Text style={styles.dropRateValue}>
                {((stats.droppedFrames / Math.max(stats.frameCount, 1)) * 100).toFixed(2)}%
              </Text>
              <Text style={styles.dropRateLabel}>
                丢帧 {stats.droppedFrames} / 总帧 {stats.frameCount}
              </Text>
            </View>
          </View>
        </ScrollView>
      )}
    </Surface>
  );
};

/**
 * 延迟柱状图组件
 */
const LatencyBar: React.FC<{
  label: string;
  value: number;
  maxValue: number;
  color: string;
}> = ({label, value, maxValue, color}) => {
  const percentage = maxValue > 0 ? (value / maxValue) * 100 : 0;

  return (
    <View style={styles.latencyBarContainer}>
      <Text style={styles.latencyBarLabel}>{label}</Text>
      <View style={styles.latencyBarTrack}>
        <View
          style={[
            styles.latencyBarFill,
            {width: `${percentage}%`, backgroundColor: color},
          ]}
        />
      </View>
      <Text style={styles.latencyBarValue}>{value.toFixed(0)}ms</Text>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    backgroundColor: theme.colors.surface,
    borderRadius: theme.roundness,
    overflow: 'hidden',
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 8,
    paddingVertical: 4,
    backgroundColor: theme.colors.surfaceVariant,
  },
  headerLeft: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  title: {
    fontSize: 16,
    fontWeight: 'bold',
    color: theme.colors.text,
  },
  content: {
    maxHeight: 400,
  },
  section: {
    padding: 12,
  },
  sectionTitle: {
    fontSize: 14,
    fontWeight: 'bold',
    color: theme.colors.text,
    marginBottom: 8,
  },
  metricsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  metricItem: {
    flex: 1,
    minWidth: '45%',
    padding: 8,
    backgroundColor: theme.colors.background,
    borderRadius: 8,
  },
  metricLabel: {
    fontSize: 11,
    color: theme.colors.textSecondary,
    marginBottom: 4,
  },
  metricValueContainer: {
    flexDirection: 'row',
    alignItems: 'baseline',
  },
  metricValue: {
    fontSize: 18,
    fontWeight: 'bold',
  },
  metricUnit: {
    fontSize: 11,
    color: theme.colors.textSecondary,
    marginLeft: 4,
  },
  divider: {
    marginVertical: 4,
  },
  latencyDistribution: {
    gap: 6,
  },
  latencyBarContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  latencyBarLabel: {
    width: 35,
    fontSize: 11,
    color: theme.colors.textSecondary,
  },
  latencyBarTrack: {
    flex: 1,
    height: 16,
    backgroundColor: theme.colors.background,
    borderRadius: 8,
    overflow: 'hidden',
  },
  latencyBarFill: {
    height: '100%',
  },
  latencyBarValue: {
    width: 50,
    fontSize: 11,
    color: theme.colors.text,
    textAlign: 'right',
  },
  dropRateContainer: {
    alignItems: 'center',
    padding: 12,
    backgroundColor: theme.colors.background,
    borderRadius: 8,
  },
  dropRateValue: {
    fontSize: 32,
    fontWeight: 'bold',
    color: theme.colors.text,
  },
  dropRateLabel: {
    fontSize: 12,
    color: theme.colors.textSecondary,
    marginTop: 4,
  },
});

export default TelemetryDashboard;
