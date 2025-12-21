import React, {useState, useEffect, useCallback} from 'react';
import {
  View,
  StyleSheet,
  ScrollView,
  FlatList,
  TouchableOpacity,
  Platform,
} from 'react-native';
import {
  Surface,
  Text,
  Button,
  IconButton,
  Divider,
  SegmentedButtons,
  Portal,
  Modal,
  Chip,
} from 'react-native-paper';
import Share from 'react-native-share';
import {logger, LogEntry, LogLevel} from '../utils/Logger';
import {theme} from '../theme';

/**
 * 工程师调试界面
 * 提供日志查看、性能分析、网络调试等工具
 */
export const EngineerScreen = () => {
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [selectedLog, setSelectedLog] = useState<LogEntry | null>(null);
  const [filterLevel, setFilterLevel] = useState<string>('all');
  const [selectedCategory, setSelectedCategory] = useState<string>('all');
  const [autoScroll, setAutoScroll] = useState(true);

  // 订阅日志更新
  useEffect(() => {
    const updateLogs = () => {
      setLogs(logger.getLogs());
    };

    const listener = () => {
      updateLogs();
    };

    logger.addListener(listener);
    updateLogs();

    return () => {
      logger.removeListener(listener);
    };
  }, []);

  // 根据筛选条件过滤日志
  const filteredLogs = logs.filter(log => {
    if (filterLevel !== 'all') {
      const levelNum = parseInt(filterLevel, 10);
      if (log.level !== levelNum) {
        return false;
      }
    }

    if (selectedCategory !== 'all' && log.category !== selectedCategory) {
      return false;
    }

    return true;
  });

  // 导出日志
  const handleExport = useCallback(async (format: 'json' | 'csv' | 'txt') => {
    let content: string;
    let mimeType: string;
    let filename: string;

    switch (format) {
      case 'json':
        content = logger.exportJSON();
        mimeType = 'application/json';
        filename = `logs_${Date.now()}.json`;
        break;
      case 'csv':
        content = logger.exportCSV();
        mimeType = 'text/csv';
        filename = `logs_${Date.now()}.csv`;
        break;
      case 'txt':
        content = logger.exportText();
        mimeType = 'text/plain';
        filename = `logs_${Date.now()}.txt`;
        break;
    }

    try {
      await Share.open({
        title: '导出日志',
        message: content,
        type: mimeType,
        filename,
      });
    } catch (error) {
      console.error('Failed to export logs:', error);
    }
  }, []);

  // 清空日志
  const handleClear = useCallback(() => {
    logger.clear();
    setLogs([]);
    setSelectedLog(null);
  }, []);

  // 生成测试日志
  const handleGenerateTestLogs = useCallback(() => {
    logger.debug('This is a debug message', 'Test');
    logger.info('This is an info message', 'Test');
    logger.warn('This is a warning message', 'Test');
    logger.error('This is an error message', 'Test');
    logger.info('Test with data', 'Test', {foo: 'bar', count: 42});
  }, []);

  // 渲染日志条目
  const renderLogItem = ({item}: {item: LogEntry}) => {
    const levelColor = getLevelColor(item.level);
    const timestamp = new Date(item.timestamp).toLocaleTimeString();

    return (
      <TouchableOpacity
        style={styles.logItem}
        onPress={() => setSelectedLog(item)}>
        <View style={styles.logHeader}>
          <Chip
            style={[styles.levelChip, {backgroundColor: levelColor}]}
            textStyle={styles.levelChipText}>
            {LogLevel[item.level]}
          </Chip>
          <Text style={styles.logTimestamp}>{timestamp}</Text>
          {item.category && (
            <Chip style={styles.categoryChip} textStyle={styles.categoryChipText}>
              {item.category}
            </Chip>
          )}
        </View>
        <Text style={styles.logMessage} numberOfLines={2}>
          {item.message}
        </Text>
      </TouchableOpacity>
    );
  };

  // 获取所有类别
  const categories = ['all', ...logger.getCategories()];

  // 统计信息
  const stats = logger.generateStats();

  return (
    <View style={styles.container}>
      {/* 标题栏 */}
      <Surface style={styles.header} elevation={2}>
        <View style={styles.headerContent}>
          <IconButton icon="cog" size={24} iconColor={theme.colors.primary} />
          <Text style={styles.headerTitle}>工程师调试</Text>
        </View>
      </Surface>

      {/* 统计信息 */}
      <Surface style={styles.statsContainer} elevation={1}>
        <View style={styles.statsRow}>
          <StatItem label="总计" value={stats.totalLogs} />
          <StatItem label="DEBUG" value={stats.debugCount} color={theme.colors.textSecondary} />
          <StatItem label="INFO" value={stats.infoCount} color={theme.colors.primary} />
          <StatItem label="WARN" value={stats.warnCount} color={theme.colors.warning} />
          <StatItem label="ERROR" value={stats.errorCount} color={theme.colors.error} />
        </View>
      </Surface>

      {/* 筛选器 */}
      <Surface style={styles.filterContainer} elevation={1}>
        <Text style={styles.filterLabel}>日志级别</Text>
        <SegmentedButtons
          value={filterLevel}
          onValueChange={setFilterLevel}
          buttons={[
            {value: 'all', label: '全部'},
            {value: '0', label: 'DEBUG'},
            {value: '1', label: 'INFO'},
            {value: '2', label: 'WARN'},
            {value: '3', label: 'ERROR'},
          ]}
        />

        <Text style={styles.filterLabel}>类别</Text>
        <ScrollView horizontal showsHorizontalScrollIndicator={false}>
          <View style={styles.categoryButtons}>
            {categories.map(category => (
              <Chip
                key={category}
                selected={selectedCategory === category}
                onPress={() => setSelectedCategory(category)}
                style={styles.categoryFilterChip}>
                {category}
              </Chip>
            ))}
          </View>
        </ScrollView>
      </Surface>

      {/* 日志列表 */}
      <FlatList
        data={filteredLogs}
        renderItem={renderLogItem}
        keyExtractor={(item, index) => `${item.timestamp}-${index}`}
        style={styles.logList}
        contentContainerStyle={styles.logListContent}
        ItemSeparatorComponent={() => <Divider />}
        ListEmptyComponent={
          <View style={styles.emptyContainer}>
            <IconButton icon="file-document-outline" size={48} iconColor={theme.colors.textSecondary} />
            <Text style={styles.emptyText}>暂无日志</Text>
          </View>
        }
      />

      {/* 底部操作栏 */}
      <Surface style={styles.actionBar} elevation={3}>
        <Button
          mode="outlined"
          onPress={handleClear}
          icon="delete"
          style={styles.actionButton}>
          清空
        </Button>
        <Button
          mode="outlined"
          onPress={() => handleExport('json')}
          icon="file-export"
          style={styles.actionButton}>
          导出
        </Button>
        <Button
          mode="outlined"
          onPress={handleGenerateTestLogs}
          icon="test-tube"
          style={styles.actionButton}>
          测试
        </Button>
        <IconButton
          icon={autoScroll ? 'arrow-down-bold' : 'arrow-down-bold-outline'}
          size={24}
          onPress={() => setAutoScroll(!autoScroll)}
          iconColor={autoScroll ? theme.colors.primary : theme.colors.textSecondary}
        />
      </Surface>

      {/* 日志详情模态框 */}
      <Portal>
        <Modal
          visible={selectedLog !== null}
          onDismiss={() => setSelectedLog(null)}
          contentContainerStyle={styles.modalContainer}>
          {selectedLog && (
            <Surface style={styles.modalContent} elevation={4}>
              <View style={styles.modalHeader}>
                <Text style={styles.modalTitle}>日志详情</Text>
                <IconButton
                  icon="close"
                  size={20}
                  onPress={() => setSelectedLog(null)}
                />
              </View>

              <Divider />

              <ScrollView style={styles.modalBody}>
                <DetailRow label="时间" value={new Date(selectedLog.timestamp).toLocaleString()} />
                <DetailRow label="级别" value={LogLevel[selectedLog.level]} />
                {selectedLog.category && (
                  <DetailRow label="类别" value={selectedLog.category} />
                )}
                <DetailRow label="消息" value={selectedLog.message} />
                {selectedLog.data && (
                  <DetailRow
                    label="数据"
                    value={JSON.stringify(selectedLog.data, null, 2)}
                    monospace
                  />
                )}
              </ScrollView>

              <Divider />

              <View style={styles.modalActions}>
                <Button
                  mode="outlined"
                  onPress={() => {
                    const text = `[${LogLevel[selectedLog.level]}] ${selectedLog.message}`;
                    Share.open({message: text});
                  }}
                  icon="share">
                  分享
                </Button>
              </View>
            </Surface>
          )}
        </Modal>
      </Portal>
    </View>
  );
};

// 统计项组件
const StatItem: React.FC<{
  label: string;
  value: number;
  color?: string;
}> = ({label, value, color = theme.colors.text}) => (
  <View style={styles.statItem}>
    <Text style={styles.statLabel}>{label}</Text>
    <Text style={[styles.statValue, {color}]}>{value}</Text>
  </View>
);

// 详情行组件
const DetailRow: React.FC<{
  label: string;
  value: string;
  monospace?: boolean;
}> = ({label, value, monospace}) => (
  <View style={styles.detailRow}>
    <Text style={styles.detailLabel}>{label}</Text>
    <Text
      style={[
        styles.detailValue,
        monospace && styles.detailValueMonospace,
      ]}>
      {value}
    </Text>
  </View>
);

// 获取日志级别颜色
const getLevelColor = (level: LogLevel): string => {
  switch (level) {
    case LogLevel.DEBUG:
      return theme.colors.textSecondary;
    case LogLevel.INFO:
      return theme.colors.primary;
    case LogLevel.WARN:
      return theme.colors.warning;
    case LogLevel.ERROR:
      return theme.colors.error;
    default:
      return theme.colors.text;
  }
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: theme.colors.background,
  },
  header: {
    backgroundColor: theme.colors.surface,
    paddingVertical: 8,
  },
  headerContent: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 8,
  },
  headerTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    color: theme.colors.text,
  },
  statsContainer: {
    margin: 16,
    padding: 12,
    backgroundColor: theme.colors.surface,
    borderRadius: theme.roundness,
  },
  statsRow: {
    flexDirection: 'row',
    justifyContent: 'space-around',
  },
  statItem: {
    alignItems: 'center',
  },
  statLabel: {
    fontSize: 11,
    color: theme.colors.textSecondary,
    marginBottom: 4,
  },
  statValue: {
    fontSize: 18,
    fontWeight: 'bold',
  },
  filterContainer: {
    marginHorizontal: 16,
    marginBottom: 16,
    padding: 12,
    backgroundColor: theme.colors.surface,
    borderRadius: theme.roundness,
  },
  filterLabel: {
    fontSize: 12,
    fontWeight: 'bold',
    color: theme.colors.text,
    marginBottom: 8,
  },
  categoryButtons: {
    flexDirection: 'row',
    gap: 8,
    paddingVertical: 4,
  },
  categoryFilterChip: {
    marginRight: 4,
  },
  logList: {
    flex: 1,
  },
  logListContent: {
    paddingBottom: 16,
  },
  logItem: {
    padding: 12,
    backgroundColor: theme.colors.surface,
  },
  logHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 4,
  },
  levelChip: {
    marginRight: 8,
    height: 20,
  },
  levelChipText: {
    fontSize: 10,
    color: '#FFFFFF',
    fontWeight: 'bold',
  },
  categoryChip: {
    height: 20,
    backgroundColor: theme.colors.surfaceVariant,
  },
  categoryChipText: {
    fontSize: 10,
  },
  logTimestamp: {
    fontSize: 11,
    color: theme.colors.textSecondary,
    marginRight: 8,
  },
  logMessage: {
    fontSize: 13,
    color: theme.colors.text,
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 48,
  },
  emptyText: {
    fontSize: 16,
    color: theme.colors.textSecondary,
  },
  actionBar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-around',
    paddingVertical: 8,
    paddingHorizontal: 16,
    backgroundColor: theme.colors.surface,
  },
  actionButton: {
    flex: 1,
    marginHorizontal: 4,
  },
  modalContainer: {
    margin: 20,
  },
  modalContent: {
    backgroundColor: theme.colors.surface,
    borderRadius: theme.roundness,
    maxHeight: '80%',
  },
  modalHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
  modalTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    color: theme.colors.text,
  },
  modalBody: {
    paddingHorizontal: 16,
    paddingVertical: 12,
    maxHeight: 400,
  },
  detailRow: {
    marginBottom: 12,
  },
  detailLabel: {
    fontSize: 12,
    fontWeight: 'bold',
    color: theme.colors.textSecondary,
    marginBottom: 4,
  },
  detailValue: {
    fontSize: 14,
    color: theme.colors.text,
  },
  detailValueMonospace: {
    fontFamily: Platform.select({ios: 'Courier', android: 'monospace'}),
  },
  modalActions: {
    flexDirection: 'row',
    justifyContent: 'flex-end',
    padding: 16,
  },
});

export default EngineerScreen;
