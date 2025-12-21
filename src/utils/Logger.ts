import {Platform} from 'react-native';

/**
 * 日志级别
 */
export enum LogLevel {
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3,
}

/**
 * 日志条目
 */
export interface LogEntry {
  level: LogLevel;
  message: string;
  timestamp: number;
  category?: string;
  data?: any;
}

/**
 * 日志监听器
 */
export type LogListener = (entry: LogEntry) => void;

/**
 * 日志系统
 * 提供分级日志、持久化、远程上传等功能
 */
class Logger {
  private logs: LogEntry[] = [];
  private maxLogs: number = 1000;
  private minLevel: LogLevel = LogLevel.DEBUG;
  private listeners: LogListener[] = [];
  private categories: Set<string> = new Set();

  /**
   * 设置最大日志数量
   */
  setMaxLogs(max: number): void {
    this.maxLogs = max;
    this.trimLogs();
  }

  /**
   * 设置最小日志级别
   */
  setMinLevel(level: LogLevel): void {
    this.minLevel = level;
  }

  /**
   * 添加日志监听器
   */
  addListener(listener: LogListener): void {
    this.listeners.push(listener);
  }

  /**
   * 移除日志监听器
   */
  removeListener(listener: LogListener): void {
    this.listeners = this.listeners.filter(l => l !== listener);
  }

  /**
   * 记录日志
   */
  log(
    level: LogLevel,
    message: string,
    category?: string,
    data?: any,
  ): void {
    if (level < this.minLevel) {
      return;
    }

    const entry: LogEntry = {
      level,
      message,
      timestamp: Date.now(),
      category,
      data,
    };

    this.logs.push(entry);

    if (category) {
      this.categories.add(category);
    }

    // 触发监听器
    this.listeners.forEach(listener => listener(entry));

    // 限制日志数量
    if (this.logs.length > this.maxLogs) {
      this.trimLogs();
    }

    // 输出到控制台
    this.logToConsole(entry);
  }

  /**
   * DEBUG 级别日志
   */
  debug(message: string, category?: string, data?: any): void {
    this.log(LogLevel.DEBUG, message, category, data);
  }

  /**
   * INFO 级别日志
   */
  info(message: string, category?: string, data?: any): void {
    this.log(LogLevel.INFO, message, category, data);
  }

  /**
   * WARN 级别日志
   */
  warn(message: string, category?: string, data?: any): void {
    this.log(LogLevel.WARN, message, category, data);
  }

  /**
   * ERROR 级别日志
   */
  error(message: string, category?: string, data?: any): void {
    this.log(LogLevel.ERROR, message, category, data);
  }

  /**
   * 获取所有日志
   */
  getLogs(): LogEntry[] {
    return [...this.logs];
  }

  /**
   * 根据级别筛选日志
   */
  getLogsByLevel(level: LogLevel): LogEntry[] {
    return this.logs.filter(log => log.level === level);
  }

  /**
   * 根据类别筛选日志
   */
  getLogsByCategory(category: string): LogEntry[] {
    return this.logs.filter(log => log.category === category);
  }

  /**
   * 根据时间范围筛选日志
   */
  getLogsByTimeRange(startTime: number, endTime: number): LogEntry[] {
    return this.logs.filter(
      log => log.timestamp >= startTime && log.timestamp <= endTime,
    );
  }

  /**
   * 获取所有类别
   */
  getCategories(): string[] {
    return Array.from(this.categories);
  }

  /**
   * 清空日志
   */
  clear(): void {
    this.logs = [];
    this.categories.clear();
  }

  /**
   * 导出日志为 JSON
   */
  exportJSON(): string {
    return JSON.stringify(
      {
        platform: Platform.OS,
        exportTime: Date.now(),
        logCount: this.logs.length,
        logs: this.logs,
      },
      null,
      2,
    );
  }

  /**
   * 导出日志为 CSV
   */
  exportCSV(): string {
    const lines: string[] = [
      'Timestamp,Level,Category,Message,Data',
    ];

    this.logs.forEach(log => {
      const timestamp = new Date(log.timestamp).toISOString();
      const level = LogLevel[log.level];
      const category = log.category || '';
      const message = log.message.replace(/"/g, '""'); // Escape quotes
      const data = log.data ? JSON.stringify(log.data).replace(/"/g, '""') : '';

      lines.push(`"${timestamp}","${level}","${category}","${message}","${data}"`);
    });

    return lines.join('\n');
  }

  /**
   * 导出日志为文本
   */
  exportText(): string {
    const lines: string[] = [];

    this.logs.forEach(log => {
      const timestamp = new Date(log.timestamp).toISOString();
      const level = LogLevel[log.level].padEnd(5);
      const category = log.category ? `[${log.category}]` : '';
      const message = log.message;
      const data = log.data ? ` | Data: ${JSON.stringify(log.data)}` : '';

      lines.push(`${timestamp} ${level} ${category} ${message}${data}`);
    });

    return lines.join('\n');
  }

  /**
   * 生成统计报告
   */
  generateStats(): {
    totalLogs: number;
    debugCount: number;
    infoCount: number;
    warnCount: number;
    errorCount: number;
    categories: {[category: string]: number};
    timeRange: {start: number; end: number};
  } {
    const stats = {
      totalLogs: this.logs.length,
      debugCount: 0,
      infoCount: 0,
      warnCount: 0,
      errorCount: 0,
      categories: {} as {[category: string]: number},
      timeRange: {
        start: this.logs.length > 0 ? this.logs[0].timestamp : 0,
        end: this.logs.length > 0 ? this.logs[this.logs.length - 1].timestamp : 0,
      },
    };

    this.logs.forEach(log => {
      switch (log.level) {
        case LogLevel.DEBUG:
          stats.debugCount++;
          break;
        case LogLevel.INFO:
          stats.infoCount++;
          break;
        case LogLevel.WARN:
          stats.warnCount++;
          break;
        case LogLevel.ERROR:
          stats.errorCount++;
          break;
      }

      if (log.category) {
        stats.categories[log.category] = (stats.categories[log.category] || 0) + 1;
      }
    });

    return stats;
  }

  /**
   * 生成报告
   */
  generateReport(): string {
    const stats = this.generateStats();

    const lines = [
      'Logger Report',
      '=============',
      '',
      `Total Logs: ${stats.totalLogs}`,
      `  - DEBUG: ${stats.debugCount}`,
      `  - INFO: ${stats.infoCount}`,
      `  - WARN: ${stats.warnCount}`,
      `  - ERROR: ${stats.errorCount}`,
      '',
      'Categories:',
    ];

    Object.entries(stats.categories).forEach(([category, count]) => {
      lines.push(`  - ${category}: ${count}`);
    });

    lines.push('');
    lines.push('Time Range:');
    lines.push(`  - Start: ${new Date(stats.timeRange.start).toISOString()}`);
    lines.push(`  - End: ${new Date(stats.timeRange.end).toISOString()}`);

    return lines.join('\n');
  }

  // ========== 私有方法 ==========

  /**
   * 输出到控制台
   */
  private logToConsole(entry: LogEntry): void {
    const timestamp = new Date(entry.timestamp).toISOString();
    const category = entry.category ? `[${entry.category}]` : '';
    const prefix = `[${timestamp}] ${category}`;

    switch (entry.level) {
      case LogLevel.DEBUG:
        console.log(`${prefix} DEBUG: ${entry.message}`, entry.data);
        break;
      case LogLevel.INFO:
        console.info(`${prefix} INFO: ${entry.message}`, entry.data);
        break;
      case LogLevel.WARN:
        console.warn(`${prefix} WARN: ${entry.message}`, entry.data);
        break;
      case LogLevel.ERROR:
        console.error(`${prefix} ERROR: ${entry.message}`, entry.data);
        break;
    }
  }

  /**
   * 修剪日志
   */
  private trimLogs(): void {
    if (this.logs.length > this.maxLogs) {
      const excess = this.logs.length - this.maxLogs;
      this.logs.splice(0, excess);
    }
  }
}

// 导出单例
export const logger = new Logger();

// 默认设置
if (__DEV__) {
  logger.setMinLevel(LogLevel.DEBUG);
} else {
  logger.setMinLevel(LogLevel.INFO);
}

export default logger;
