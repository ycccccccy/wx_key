import 'package:shared_preferences/shared_preferences.dart';

/// 微信数据库密钥存储服务
/// 使用 SharedPreferences 进行持久化存储
class KeyStorage {
  static const String _keyWechatDbKey = 'wechat_db_key';
  static const String _keyTimestamp = 'key_timestamp';
  static const String _keyDllPath = 'dll_path';
  static const String _keyWechatDirectory = 'wechat_directory';
  static const String _keyImageXorKey = 'image_xor_key';
  static const String _keyImageAesKey = 'image_aes_key';
  static const String _keyImageKeyTimestamp = 'image_key_timestamp';

  /// 保存微信数据库密钥
  /// [key] 32字节密钥的十六进制字符串（64个字符）
  /// [timestamp] 密钥获取时间，如果为null则使用当前时间
  static Future<bool> saveKey(String key, [DateTime? timestamp]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final success = await prefs.setString(_keyWechatDbKey, key);
      if (success) {
        final time = timestamp ?? DateTime.now();
        await prefs.setString(_keyTimestamp, time.toIso8601String());
      }
      return success;
    } catch (e) {
      print('保存密钥失败: $e');
      return false;
    }
  }

  /// 获取保存的微信数据库密钥
  /// 返回密钥字符串，如果不存在则返回null
  static Future<String?> getKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyWechatDbKey);
    } catch (e) {
      print('读取密钥失败: $e');
      return null;
    }
  }

  /// 检查是否已保存密钥
  static Future<bool> hasKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey(_keyWechatDbKey);
    } catch (e) {
      print('检查密钥失败: $e');
      return false;
    }
  }

  /// 获取密钥保存时间
  /// 返回保存时间，如果不存在则返回null
  static Future<DateTime?> getKeyTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestampStr = prefs.getString(_keyTimestamp);
      if (timestampStr != null) {
        return DateTime.parse(timestampStr);
      }
      return null;
    } catch (e) {
      print('读取密钥时间戳失败: $e');
      return null;
    }
  }

  /// 清除保存的密钥
  static Future<bool> clearKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final success1 = await prefs.remove(_keyWechatDbKey);
      final success2 = await prefs.remove(_keyTimestamp);
      return success1 && success2;
    } catch (e) {
      print('清除密钥失败: $e');
      return false;
    }
  }

  /// 保存DLL文件路径
  static Future<bool> saveDllPath(String path) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_keyDllPath, path);
    } catch (e) {
      print('保存DLL路径失败: $e');
      return false;
    }
  }

  /// 获取保存的DLL文件路径
  static Future<String?> getDllPath() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyDllPath);
    } catch (e) {
      print('读取DLL路径失败: $e');
      return null;
    }
  }

  /// 清除保存的DLL路径
  static Future<bool> clearDllPath() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.remove(_keyDllPath);
    } catch (e) {
      print('清除DLL路径失败: $e');
      return false;
    }
  }

  /// 获取密钥信息（包含密钥和时间戳）
  static Future<Map<String, dynamic>?> getKeyInfo() async {
    try {
      final key = await getKey();
      if (key == null) return null;
      
      final timestamp = await getKeyTimestamp();
      return {
        'key': key,
        'timestamp': timestamp,
        'formattedTime': timestamp != null 
            ? '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}'
            : '未知时间'
      };
    } catch (e) {
      print('获取密钥信息失败: $e');
      return null;
    }
  }

  /// 保存微信安装目录
  static Future<bool> saveWechatDirectory(String directory) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_keyWechatDirectory, directory);
    } catch (e) {
      print('保存微信目录失败: $e');
      return false;
    }
  }

  /// 获取保存的微信安装目录
  static Future<String?> getWechatDirectory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyWechatDirectory);
    } catch (e) {
      print('读取微信目录失败: $e');
      return null;
    }
  }

  /// 清除保存的微信目录
  static Future<bool> clearWechatDirectory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.remove(_keyWechatDirectory);
    } catch (e) {
      print('清除微信目录失败: $e');
      return false;
    }
  }

  /// 保存图片XOR密钥
  static Future<bool> saveImageXorKey(int xorKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setInt(_keyImageXorKey, xorKey);
    } catch (e) {
      print('保存XOR密钥失败: $e');
      return false;
    }
  }

  /// 获取图片XOR密钥
  static Future<int?> getImageXorKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_keyImageXorKey);
    } catch (e) {
      print('读取XOR密钥失败: $e');
      return null;
    }
  }

  /// 保存图片AES密钥
  static Future<bool> saveImageAesKey(String aesKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final success = await prefs.setString(_keyImageAesKey, aesKey);
      if (success) {
        await prefs.setString(_keyImageKeyTimestamp, DateTime.now().toIso8601String());
      }
      return success;
    } catch (e) {
      print('保存AES密钥失败: $e');
      return false;
    }
  }

  /// 获取图片AES密钥
  static Future<String?> getImageAesKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyImageAesKey);
    } catch (e) {
      print('读取AES密钥失败: $e');
      return null;
    }
  }

  /// 保存图片密钥（同时保存XOR和AES）
  static Future<bool> saveImageKeys(int xorKey, String aesKey) async {
    try {
      final xorSuccess = await saveImageXorKey(xorKey);
      final aesSuccess = await saveImageAesKey(aesKey);
      return xorSuccess && aesSuccess;
    } catch (e) {
      print('保存图片密钥失败: $e');
      return false;
    }
  }

  /// 获取图片密钥信息
  static Future<Map<String, dynamic>?> getImageKeyInfo() async {
    try {
      final xorKey = await getImageXorKey();
      final aesKey = await getImageAesKey();
      
      if (xorKey == null || aesKey == null) return null;

      final prefs = await SharedPreferences.getInstance();
      final timestampStr = prefs.getString(_keyImageKeyTimestamp);
      DateTime? timestamp;
      if (timestampStr != null) {
        timestamp = DateTime.parse(timestampStr);
      }

      return {
        'xorKey': xorKey,
        'aesKey': aesKey,
        'timestamp': timestamp,
        'formattedTime': timestamp != null
            ? '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}'
            : '未知时间'
      };
    } catch (e) {
      print('获取图片密钥信息失败: $e');
      return null;
    }
  }

  /// 清除图片密钥
  static Future<bool> clearImageKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final success1 = await prefs.remove(_keyImageXorKey);
      final success2 = await prefs.remove(_keyImageAesKey);
      final success3 = await prefs.remove(_keyImageKeyTimestamp);
      return success1 && success2 && success3;
    } catch (e) {
      print('清除图片密钥失败: $e');
      return false;
    }
  }
}
