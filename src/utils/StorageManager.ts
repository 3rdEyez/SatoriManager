/**
 * Storage Manager
 * 持久化存储管理器 - 用于保存和加载配置
 */

import AsyncStorage from '@react-native-async-storage/async-storage';
import { MindReadingConfig } from '../types';
import { MIND_READING_DEFAULTS } from '../constants/MindReadingDefaults';

const STORAGE_KEY = 'mind_reading_config';

/**
 * Storage Manager Class
 */
export class StorageManager {
  /**
   * 保存读心功能配置
   */
  static async saveMindReadingConfig(config: MindReadingConfig): Promise<void> {
    try {
      // 对 API Key 进行简单编码
      const encodedConfig = {
        ...config,
        qianwenApiKey: StorageManager.encryptApiKey(config.qianwenApiKey),
      };

      await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(encodedConfig));
      console.log('[StorageManager] Config saved successfully');
    } catch (error) {
      console.error('[StorageManager] Failed to save config:', error);
      throw error;
    }
  }

  /**
   * 加载读心功能配置
   */
  static async getMindReadingConfig(): Promise<MindReadingConfig> {
    try {
      const data = await AsyncStorage.getItem(STORAGE_KEY);

      if (!data) {
        console.log('[StorageManager] No saved config found, using defaults');
        return {...MIND_READING_DEFAULTS};
      }

      const encodedConfig = JSON.parse(data);

      // 解码 API Key
      return {
        ...encodedConfig,
        qianwenApiKey: StorageManager.decryptApiKey(encodedConfig.qianwenApiKey || ''),
      };
    } catch (error) {
      console.error('[StorageManager] Failed to load config:', error);
      return {...MIND_READING_DEFAULTS};
    }
  }

  /**
   * 清除配置
   */
  static async clearMindReadingConfig(): Promise<void> {
    try {
      await AsyncStorage.removeItem(STORAGE_KEY);
      console.log('[StorageManager] Config cleared successfully');
    } catch (error) {
      console.error('[StorageManager] Failed to clear config:', error);
      throw error;
    }
  }

  /**
   * 简单加密 API Key (Base64 编码)
   * 注意：这不是真正的加密，只是基础混淆
   */
  static encryptApiKey(key: string): string {
    if (!key) return '';
    // 使用 Base64 编码
    return Buffer.from(key).toString('base64');
  }

  /**
   * 解密 API Key
   */
  static decryptApiKey(encryptedKey: string): string {
    if (!encryptedKey) return '';
    try {
      // Decode and verify by re-encoding
      const decoded = Buffer.from(encryptedKey, 'base64').toString();
      // Verify the base64 is valid by checking if re-encoding matches
      const reEncoded = Buffer.from(decoded).toString('base64');
      // If re-encoded doesn't match original, the base64 was invalid
      if (reEncoded !== encryptedKey) {
        console.warn('[StorageManager] Invalid base64 detected, returning empty string');
        return '';
      }
      return decoded;
    } catch (error) {
      console.error('[StorageManager] Failed to decrypt API key:', error);
      return '';
    }
  }
}
