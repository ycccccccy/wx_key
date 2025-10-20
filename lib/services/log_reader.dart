import 'dart:io';
import 'dart:async';

/// 日志文件读取服务
/// 读取DLL写入的日志文件，获取状态和密钥信息
class LogReader {
  static String get logFilePath {
    final tempDir = Directory.systemTemp.path;
    return '$tempDir\\wx_key_status.log';
  }

  /// 清空日志文件
  static Future<void> clearLog() async {
    try {
      final logFile = File(logFilePath);
      if (await logFile.exists()) {
        await logFile.writeAsString('');
      }
    } catch (e) {
      // 忽略清空日志错误
    }
  }

  /// 读取日志文件的所有内容
  static Future<List<String>> readAllLines() async {
    try {
      final logFile = File(logFilePath);
      if (!await logFile.exists()) {
        return [];
      }
      
      final content = await logFile.readAsString();
      if (content.isEmpty) {
        return [];
      }
      
      return content.split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// 解析日志行，返回类型和消息
  static Map<String, String>? parseLogLine(String line) {
    if (line.isEmpty) return null;
    
    final colonIndex = line.indexOf(':');
    if (colonIndex == -1) return null;
    
    final type = line.substring(0, colonIndex).trim();
    final message = line.substring(colonIndex + 1).trim();
    
    return {'type': type, 'message': message};
  }

  /// 从日志中提取密钥
  static Future<String?> extractKey() async {
    try {
      final lines = await readAllLines();
      for (final line in lines) {
        if (line.startsWith('KEY:')) {
          return line.substring(4).trim();
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 获取所有日志消息（不包括密钥行）
  static Future<List<Map<String, String>>> getLogMessages() async {
    try {
      final lines = await readAllLines();
      final messages = <Map<String, String>>[];
      
      for (final line in lines) {
        if (line.startsWith('KEY:')) {
          continue;
        }
        final parsed = parseLogLine(line);
        if (parsed != null) {
          messages.add(parsed);
        }
      }
      
      return messages;
    } catch (e) {
      return [];
    }
  }

  /// 创建一个定期轮询日志文件的流
  static Stream<Map<String, dynamic>> createPollingStream({
    Duration interval = const Duration(milliseconds: 500),
  }) {
    final controller = StreamController<Map<String, dynamic>>();
    Timer? timer;
    Set<String> processedLines = {};
    
    timer = Timer.periodic(interval, (t) async {
      try {
        final lines = await readAllLines();
        
        for (final line in lines) {
          if (processedLines.contains(line)) {
            continue;
          }
          
          processedLines.add(line);
          
          if (line.startsWith('KEY:')) {
            final key = line.substring(4).trim();
            controller.add({'type': 'key', 'data': key});
          } else {
            final parsed = parseLogLine(line);
            if (parsed != null) {
              controller.add({'type': 'log', 'data': parsed});
            }
          }
        }
      } catch (e) {
        // 忽略读取错误
      }
    });
    
    controller.onCancel = () {
      timer?.cancel();
    };
    
    return controller.stream;
  }
}

