/**
 * Mind Reading Feature - Default Configuration
 * 读心功能默认配置
 */

import { MindReadingConfig } from '../types';

/**
 * 默认读心功能配置
 */
export const MIND_READING_DEFAULTS: MindReadingConfig = {
  enabled: false,
  qianwenApiKey: '',
  customPrompt: '根据这个人的表情和神态，分析他此刻在想什么。请用简练的语言回答。',
  stabilityThreshold: 1000, // 1 second
  minCaptureInterval: 10000, // 10 seconds
  serverPort: 8080,
};

/**
 * 千问 API 配置
 */
export const QIANWEN_API_CONFIG = {
  baseURL: 'https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation',
  model: 'qwen-vl-max',
  timeout: 30000, // 30 seconds
  maxRetries: 3,
} as const;

/**
 * WebSocket 服务器配置
 */
export const WEBSOCKET_SERVER_CONFIG = {
  maxClients: 10,
  heartbeatInterval: 30000, // 30 seconds
} as const;
