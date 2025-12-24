/**
 * StorageManager Tests
 */

import { StorageManager } from '../../src/utils/StorageManager';
import { MindReadingConfig, MIND_READING_DEFAULTS } from '../../src/constants/MindReadingDefaults';
import AsyncStorage from '@react-native-async-storage/async-storage';

// Mock AsyncStorage
jest.mock('@react-native-async-storage/async-storage');

describe('StorageManager', () => {
  const mockConfig: MindReadingConfig = {
    enabled: true,
    qianwenApiKey: 'test-api-key-12345',
    customPrompt: 'Test prompt for mind reading',
    stabilityThreshold: 2000,
    minCaptureInterval: 15000,
    serverPort: 9090,
  };

  beforeEach(() => {
    jest.resetAllMocks();
  });

  describe('Saving Config', () => {
    it('should save config to AsyncStorage', async () => {
      await StorageManager.saveMindReadingConfig(mockConfig);

      expect(AsyncStorage.setItem).toHaveBeenCalledWith(
        'mind_reading_config',
        expect.stringContaining('"enabled":true'),
      );
    });

    it('should encrypt API key before saving', async () => {
      await StorageManager.saveMindReadingConfig(mockConfig);

      const savedData = JSON.parse((AsyncStorage.setItem as jest.Mock).mock.calls[0][1]);

      // API key should be base64 encoded (not plain text)
      expect(savedData.qianwenApiKey).toBe(Buffer.from('test-api-key-12345').toString('base64'));
      expect(savedData.qianwenApiKey).not.toBe('test-api-key-12345');
    });

    it('should handle empty API key', async () => {
      const configWithEmptyKey = { ...mockConfig, qianwenApiKey: '' };

      await StorageManager.saveMindReadingConfig(configWithEmptyKey);

      const savedData = JSON.parse((AsyncStorage.setItem as jest.Mock).mock.calls[0][1]);
      expect(savedData.qianwenApiKey).toBe('');
    });

    it('should handle save errors gracefully', async () => {
      (AsyncStorage.setItem as jest.Mock).mockRejectedValue(new Error('Storage error'));

      await expect(StorageManager.saveMindReadingConfig(mockConfig)).rejects.toThrow('Storage error');
    });
  });

  describe('Loading Config', () => {
    it('should load config from AsyncStorage', async () => {
      const encryptedKey = Buffer.from('test-api-key-12345').toString('base64');
      const savedData = { ...mockConfig, qianwenApiKey: encryptedKey };

      (AsyncStorage.getItem as jest.Mock).mockResolvedValue(JSON.stringify(savedData));

      const loaded = await StorageManager.getMindReadingConfig();

      expect(loaded).toEqual(mockConfig);
    });

    it('should decrypt API key after loading', async () => {
      const encryptedKey = Buffer.from('test-api-key-12345').toString('base64');
      const savedData = { ...mockConfig, qianwenApiKey: encryptedKey };

      (AsyncStorage.getItem as jest.Mock).mockResolvedValue(JSON.stringify(savedData));

      const loaded = await StorageManager.getMindReadingConfig();

      expect(loaded.qianwenApiKey).toBe('test-api-key-12345');
    });

    it('should return defaults when no saved config', async () => {
      (AsyncStorage.getItem as jest.Mock).mockResolvedValue(null);

      const loaded = await StorageManager.getMindReadingConfig();

      expect(loaded).toEqual(MIND_READING_DEFAULTS);
    });

    it('should handle load errors gracefully', async () => {
      (AsyncStorage.getItem as jest.Mock).mockRejectedValue(new Error('Read error'));

      const loaded = await StorageManager.getMindReadingConfig();

      expect(loaded).toEqual(MIND_READING_DEFAULTS);
    });

    it('should handle corrupted JSON data', async () => {
      (AsyncStorage.getItem as jest.Mock).mockResolvedValue('invalid json{{{');

      const loaded = await StorageManager.getMindReadingConfig();

      expect(loaded).toEqual(MIND_READING_DEFAULTS);
    });

    it('should handle corrupted base64 data', async () => {
      const savedData = { ...mockConfig, qianwenApiKey: 'not-valid-base64!!!' };

      (AsyncStorage.getItem as jest.Mock).mockResolvedValue(JSON.stringify(savedData));

      const loaded = await StorageManager.getMindReadingConfig();

      // Should still load, but API key will be empty due to decryption failure
      expect(loaded.enabled).toBe(true);
      expect(loaded.qianwenApiKey).toBe('');
    });
  });

  describe('Clearing Config', () => {
    it('should clear config from AsyncStorage', async () => {
      await StorageManager.clearMindReadingConfig();

      expect(AsyncStorage.removeItem).toHaveBeenCalledWith('mind_reading_config');
    });

    it('should handle clear errors gracefully', async () => {
      (AsyncStorage.removeItem as jest.Mock).mockRejectedValue(new Error('Clear error'));

      await expect(StorageManager.clearMindReadingConfig()).rejects.toThrow('Clear error');
    });
  });

  describe('API Key Encryption', () => {
    it('should encrypt key to base64', () => {
      const key = 'my-secret-api-key';
      const encrypted = StorageManager.encryptApiKey(key);

      expect(encrypted).toBe(Buffer.from(key).toString('base64'));
      expect(encrypted).not.toBe(key);
    });

    it('should decrypt base64 to original key', () => {
      const key = 'my-secret-api-key';
      const encrypted = StorageManager.encryptApiKey(key);
      const decrypted = StorageManager.decryptApiKey(encrypted);

      expect(decrypted).toBe(key);
    });

    it('should handle empty string', () => {
      const encrypted = StorageManager.encryptApiKey('');
      const decrypted = StorageManager.decryptApiKey(encrypted);

      expect(encrypted).toBe('');
      expect(decrypted).toBe('');
    });

    it('should handle special characters', () => {
      const key = 'test-key-with-special-chars-!@#$%^&*()';
      const encrypted = StorageManager.encryptApiKey(key);
      const decrypted = StorageManager.decryptApiKey(encrypted);

      expect(decrypted).toBe(key);
    });

    it('should handle unicode characters', () => {
      const key = 'test-中文-api-key-日本語';
      const encrypted = StorageManager.encryptApiKey(key);
      const decrypted = StorageManager.decryptApiKey(encrypted);

      expect(decrypted).toBe(key);
    });

    it('should handle long keys', () => {
      const key = 'a'.repeat(1000);
      const encrypted = StorageManager.encryptApiKey(key);
      const decrypted = StorageManager.decryptApiKey(encrypted);

      expect(decrypted).toBe(key);
    });
  });

  describe('End-to-End Flow', () => {
    it('should save and load config correctly', async () => {
      await StorageManager.saveMindReadingConfig(mockConfig);

      // Simulate AsyncStorage behavior
      const savedData = JSON.parse((AsyncStorage.setItem as jest.Mock).mock.calls[0][1]);
      (AsyncStorage.getItem as jest.Mock).mockResolvedValue(JSON.stringify(savedData));

      const loaded = await StorageManager.getMindReadingConfig();

      expect(loaded).toEqual(mockConfig);
    });

    it('should preserve all config fields through save/load cycle', async () => {
      await StorageManager.saveMindReadingConfig(mockConfig);

      const savedData = JSON.parse((AsyncStorage.setItem as jest.Mock).mock.calls[0][1]);
      (AsyncStorage.getItem as jest.Mock).mockResolvedValue(JSON.stringify(savedData));

      const loaded = await StorageManager.getMindReadingConfig();

      expect(loaded.enabled).toBe(mockConfig.enabled);
      expect(loaded.customPrompt).toBe(mockConfig.customPrompt);
      expect(loaded.stabilityThreshold).toBe(mockConfig.stabilityThreshold);
      expect(loaded.minCaptureInterval).toBe(mockConfig.minCaptureInterval);
      expect(loaded.serverPort).toBe(mockConfig.serverPort);
      expect(loaded.qianwenApiKey).toBe(mockConfig.qianwenApiKey);
    });
  });
});
