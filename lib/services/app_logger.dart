import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as path;

/// 应用日志服务
/// 记录应用运行过程中的关键操作和错误信息
class AppLogger {
  static String? _logFilePath;
  static final _buffer = <String>[];
  static Timer? _flushTimer;
  static const int _maxBufferSize = 50;

  /// 获取日志文件路径
  static String get logFilePath {
    if (_logFilePath != null) return _logFilePath!;
    
    final appDataDir = Platform.environment['APPDATA'] ?? Platform.environment['USERPROFILE'];
    if (appDataDir != null) {
      final logDir = path.join(appDataDir, 'wx_key');
      Directory(logDir).createSync(recursive: true);
      _logFilePath = path.join(logDir, 'app.log');
    } else {
      final tempDir = Directory.systemTemp.path;
      _logFilePath = path.join(tempDir, 'wx_key_app.log');
    }
    
    return _logFilePath!;
  }

  /// 初始化日志服务
  static Future<void> init() async {
    try {
      // 检查日志文件大小，如果超过10MB则清空
      final logFile = File(logFilePath);
      if (await logFile.exists()) {
        final fileSize = await logFile.length();
        if (fileSize > 10 * 1024 * 1024) {
          await logFile.writeAsString('');
          await _writeLog('INFO', '日志文件过大已自动清空');
        }
      }
      
      await info('应用启动');
      
      // 启动定时刷新，每5秒自动写入缓冲区
      _flushTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        _flushBuffer();
      });
    } catch (e) {
      print('[AppLogger] 初始化失败: $e');
    }
  }

  /// 关闭日志服务
  static Future<void> close() async {
    _flushTimer?.cancel();
    await _flushBuffer();
    await info('应用关闭');
  }

  /// 记录信息日志
  static Future<void> info(String message) async {
    await _log('INFO', message);
  }

  /// 记录成功日志
  static Future<void> success(String message) async {
    await _log('SUCCESS', message);
  }

  /// 记录警告日志
  static Future<void> warning(String message) async {
    await _log('WARNING', message);
  }

  /// 记录错误日志
  static Future<void> error(String message, [Object? error, StackTrace? stackTrace]) async {
    var logMessage = message;
    if (error != null) {
      logMessage += '\n错误详情: $error';
    }
    if (stackTrace != null) {
      logMessage += '\n堆栈跟踪:\n$stackTrace';
    }
    await _log('ERROR', logMessage);
  }

  /// 内部日志方法
  static Future<void> _log(String level, String message) async {
    try {
      final timestamp = DateTime.now().toString().substring(0, 23);
      final logLine = '[$timestamp] [$level] $message';
      
      // 添加到缓冲区
      _buffer.add(logLine);
      
      // 如果缓冲区满了，立即写入
      if (_buffer.length >= _maxBufferSize) {
        await _flushBuffer();
      }
    } catch (e) {
      print('[AppLogger] 记录日志失败: $e');
    }
  }

  /// 直接写入日志（用于初始化时的特殊情况）
  static Future<void> _writeLog(String level, String message) async {
    try {
      final timestamp = DateTime.now().toString().substring(0, 23);
      final logLine = '[$timestamp] [$level] $message\n';
      
      final logFile = File(logFilePath);
      await logFile.writeAsString(logLine, mode: FileMode.append);
    } catch (e) {
      print('[AppLogger] 写入日志失败: $e');
    }
  }

  /// 刷新缓冲区到文件
  static Future<void> _flushBuffer() async {
    if (_buffer.isEmpty) return;
    
    try {
      final logFile = File(logFilePath);
      final content = _buffer.join('\n') + '\n';
      await logFile.writeAsString(content, mode: FileMode.append);
      _buffer.clear();
    } catch (e) {
      print('[AppLogger] 刷新缓冲区失败: $e');
    }
  }

  /// 清空日志文件
  static Future<void> clearLog() async {
    try {
      final logFile = File(logFilePath);
      if (await logFile.exists()) {
        await logFile.writeAsString('');
      }
      await info('日志文件已清空');
    } catch (e) {
      print('[AppLogger] 清空日志失败: $e');
    }
  }

  /// 打开日志文件
  static Future<bool> openLogFile() async {
    try {
      final logFile = File(logFilePath);
      if (!await logFile.exists()) {
        await logFile.writeAsString('');
      }
      
      // 刷新缓冲区确保最新日志已写入
      await _flushBuffer();
      
      // 使用系统默认程序打开日志文件
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', logFilePath]);
      }
      
      return true;
    } catch (e) {
      print('[AppLogger] 打开日志文件失败: $e');
      return false;
    }
  }

  /// 获取日志文件大小（格式化）
  static Future<String> getLogFileSize() async {
    try {
      final logFile = File(logFilePath);
      if (!await logFile.exists()) {
        return '0 B';
      }
      
      final bytes = await logFile.length();
      if (bytes < 1024) {
        return '$bytes B';
      } else if (bytes < 1024 * 1024) {
        return '${(bytes / 1024).toStringAsFixed(2)} KB';
      } else {
        return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
      }
    } catch (e) {
      return '未知';
    }
  }
}

