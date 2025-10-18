import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// 命名管道监听服务
/// 监听DLL发送的微信数据库密钥和日志消息
class PipeListener {
  static const String _keyPipeName = r'\\.\pipe\WeChatKeyPipe';
  static const String _logPipeName = r'\\.\pipe\WeChatLogPipe';
  static bool _isListening = false;
  static StreamController<String>? _keyController;
  static StreamController<Map<String, String>>? _logController;
  static Isolate? _keyListenerIsolate;
  static Isolate? _logListenerIsolate;
  static SendPort? _keySendPort;
  static SendPort? _logSendPort;

  /// 获取密钥流
  /// 当收到密钥时会触发此流
  static Stream<String> get keyStream {
    _keyController ??= StreamController<String>.broadcast();
    return _keyController!.stream;
  }

  /// 获取日志流
  /// 当收到日志消息时会触发此流
  static Stream<Map<String, String>> get logStream {
    _logController ??= StreamController<Map<String, String>>.broadcast();
    return _logController!.stream;
  }

  /// 开始监听命名管道
  /// 返回是否成功启动监听
  static Future<bool> startListening() async {
    if (_isListening) {
      print('[PipeListener] 已经在监听中');
      return true;
    }

    try {
      // 创建密钥接收端口
      final keyReceivePort = ReceivePort();
      _keySendPort = keyReceivePort.sendPort;

      // 创建日志接收端口
      final logReceivePort = ReceivePort();
      _logSendPort = logReceivePort.sendPort;

      // 启动密钥监听隔离
      _keyListenerIsolate = await Isolate.spawn(
        _keyPipeListenerIsolate,
        _keySendPort!,
      );

      // 启动日志监听隔离
      _logListenerIsolate = await Isolate.spawn(
        _logPipeListenerIsolate,
        _logSendPort!,
      );

      // 监听来自密钥隔离的消息
      keyReceivePort.listen((message) {
        if (message is String) {
          print('[PipeListener] 收到密钥数据');
          _keyController?.add(message);
        }
      });

      // 监听来自日志隔离的消息
      logReceivePort.listen((message) {
        if (message is String) {
          // 解析日志消息格式: "TYPE:message"
          final parts = message.split(':');
          if (parts.length >= 2) {
            final type = parts[0];
            final msg = parts.sublist(1).join(':');
            _logController?.add({'type': type, 'message': msg});
          }
        }
      });

      _isListening = true;
      print('[PipeListener] 命名管道监听已启动');
      return true;
    } catch (e) {
      print('[PipeListener] 启动监听失败: $e');
      return false;
    }
  }

  /// 停止监听命名管道
  static Future<void> stopListening() async {
    if (!_isListening) return;

    try {
      _keyListenerIsolate?.kill();
      _keyListenerIsolate = null;
      _logListenerIsolate?.kill();
      _logListenerIsolate = null;
      _keySendPort = null;
      _logSendPort = null;
      _isListening = false;
      await _keyController?.close();
      _keyController = null;
      await _logController?.close();
      _logController = null;
      print('[PipeListener] 命名管道监听已停止');
    } catch (e) {
      print('[PipeListener] 停止监听失败: $e');
    }
  }

  /// 检查是否正在监听
  static bool get isListening => _isListening;


  /// 密钥管道监听隔离函数
  static void _keyPipeListenerIsolate(SendPort sendPort) {
    while (true) {
      try {
        // 创建命名管道
        final pipeName = _keyPipeName.toNativeUtf16();
        final hPipe = CreateNamedPipe(
          pipeName.cast(),
          PIPE_ACCESS_INBOUND,
          PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT,
          1, // 最大实例数
          1024, // 输出缓冲区大小
          1024, // 输入缓冲区大小
          0, // 默认超时
          nullptr, // 默认安全属性
        );

        if (hPipe == INVALID_HANDLE_VALUE) {
          free(pipeName);
          sleep(const Duration(seconds: 2));
          continue;
        }

        // 等待客户端连接
        final connected = ConnectNamedPipe(hPipe, nullptr);
        if (connected == 0) {
          final error = GetLastError();
          if (error != ERROR_PIPE_CONNECTED) {
            CloseHandle(hPipe);
            free(pipeName);
            sleep(const Duration(milliseconds: 500));
            continue;
          }
        }

        // 读取数据 - 立即读取，不等待
        final buffer = calloc<Uint8>(1024);
        final bytesRead = calloc<DWORD>();

        try {
          // 设置管道为消息模式
          final mode = calloc<Uint32>();
          mode.value = PIPE_READMODE_MESSAGE;
          SetNamedPipeHandleState(hPipe, mode, nullptr, nullptr);
          free(mode);
          
          final readResult = ReadFile(hPipe, buffer.cast(), 1024, bytesRead, nullptr);
          
          if (readResult != 0 && bytesRead.value > 0) {
            // 使用 UTF-8 解码，支持中文
            final bytes = buffer.asTypedList(bytesRead.value);
            final data = utf8.decode(bytes, allowMalformed: true).trim();
            
            if (data.isNotEmpty) {
              sendPort.send(data);
            }
          }
        } finally {
          free(buffer);
          free(bytesRead);
        }

        // 断开连接
        DisconnectNamedPipe(hPipe);
        CloseHandle(hPipe);
        free(pipeName);

        // 短暂等待后重新创建管道
        sleep(const Duration(milliseconds: 100));

      } catch (e) {
        sleep(const Duration(seconds: 5));
      }
    }
  }

  /// 日志管道监听隔离函数
  static void _logPipeListenerIsolate(SendPort sendPort) {
    while (true) {
      try {
        final pipeName = _logPipeName.toNativeUtf16();
        final hPipe = CreateNamedPipe(
          pipeName.cast(),
          PIPE_ACCESS_INBOUND,
          PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT,
          10, // 允许多个实例
          1024,
          1024,
          0,
          nullptr,
        );

        if (hPipe == INVALID_HANDLE_VALUE) {
          free(pipeName);
          sleep(const Duration(seconds: 1));
          continue;
        }

        final connected = ConnectNamedPipe(hPipe, nullptr);
        if (connected == 0) {
          final error = GetLastError();
          if (error != ERROR_PIPE_CONNECTED) {
            CloseHandle(hPipe);
            free(pipeName);
            sleep(const Duration(milliseconds: 100));
            continue;
          }
        }

        final buffer = calloc<Uint8>(1024);
        final bytesRead = calloc<DWORD>();

        try {
          final mode = calloc<Uint32>();
          mode.value = PIPE_READMODE_MESSAGE;
          SetNamedPipeHandleState(hPipe, mode, nullptr, nullptr);
          free(mode);
          
          final readResult = ReadFile(hPipe, buffer.cast(), 1024, bytesRead, nullptr);
          
          if (readResult != 0 && bytesRead.value > 0) {
            // 使用 UTF-8 解码，支持中文
            final bytes = buffer.asTypedList(bytesRead.value);
            final data = utf8.decode(bytes, allowMalformed: true).trim();
            
            if (data.isNotEmpty) {
              sendPort.send(data);
            }
          }
        } finally {
          free(buffer);
          free(bytesRead);
        }

        DisconnectNamedPipe(hPipe);
        CloseHandle(hPipe);
        free(pipeName);
        sleep(const Duration(milliseconds: 50));

      } catch (e) {
        sleep(const Duration(seconds: 1));
      }
    }
  }
}
