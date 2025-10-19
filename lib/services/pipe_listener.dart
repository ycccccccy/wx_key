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
  static ReceivePort? _keyReceivePort;
  static ReceivePort? _logReceivePort;
  static SendPort? _keyControlSendPort;
  static SendPort? _logControlSendPort;

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
      _keyReceivePort = ReceivePort();
      
      // 创建日志接收端口
      _logReceivePort = ReceivePort();

      // 创建密钥隔离的通信参数
      final keyParams = _IsolateParams(
        dataSendPort: _keyReceivePort!.sendPort,
        pipeName: _keyPipeName,
        isKeyPipe: true,
      );

      // 创建日志隔离的通信参数
      final logParams = _IsolateParams(
        dataSendPort: _logReceivePort!.sendPort,
        pipeName: _logPipeName,
        isKeyPipe: false,
      );

      // 启动密钥监听隔离
      _keyListenerIsolate = await Isolate.spawn(
        _pipeListenerIsolate,
        keyParams,
      );

      // 启动日志监听隔离
      _logListenerIsolate = await Isolate.spawn(
        _pipeListenerIsolate,
        logParams,
      );

      // 监听来自密钥隔离的消息
      _keyReceivePort!.listen((message) {
        if (message is SendPort) {
          _keyControlSendPort = message;
        } else if (message is String) {
          print('[PipeListener] 收到密钥数据');
          _keyController?.add(message);
        }
      });

      // 监听来自日志隔离的消息
      _logReceivePort!.listen((message) {
        if (message is SendPort) {
          _logControlSendPort = message;
        } else if (message is String) {
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
    if (!_isListening) {
      print('[PipeListener] 已经停止，无需重复操作');
      return;
    }

    print('[PipeListener] 开始停止监听...');
    
    try {
      // 发送停止信号给 isolate
      _keyControlSendPort?.send('stop');
      _logControlSendPort?.send('stop');
      print('[PipeListener] 已发送停止信号');
      
      // 等待一小段时间让 isolate 正常退出
      await Future.delayed(const Duration(milliseconds: 200));
      
      // 强制关闭 isolate
      _keyListenerIsolate?.kill(priority: Isolate.immediate);
      _keyListenerIsolate = null;
      _logListenerIsolate?.kill(priority: Isolate.immediate);
      _logListenerIsolate = null;
      print('[PipeListener] Isolate 已强制关闭');
      
      // 关闭接收端口
      _keyReceivePort?.close();
      _keyReceivePort = null;
      _logReceivePort?.close();
      _logReceivePort = null;
      
      _keyControlSendPort = null;
      _logControlSendPort = null;
      _isListening = false;
      
      await _keyController?.close();
      _keyController = null;
      await _logController?.close();
      _logController = null;
      print('[PipeListener] 命名管道监听已完全停止');
    } catch (e) {
      print('[PipeListener] 停止监听失败: $e');
      // 即使出错也要设置状态
      _isListening = false;
    }
  }

  /// 检查是否正在监听
  static bool get isListening => _isListening;

  /// 管道监听隔离函数
  static void _pipeListenerIsolate(_IsolateParams params) {
    // 创建控制接收端口用于接收停止信号
    final controlPort = ReceivePort();
    params.dataSendPort.send(controlPort.sendPort);
    
    bool shouldStop = false;
    int consecutiveErrors = 0;
    final maxConsecutiveErrors = 5;
    
    // 监听停止信号
    controlPort.listen((message) {
      if (message == 'stop') {
        shouldStop = true;
        controlPort.close();
      }
    });
    
    while (!shouldStop) {
      try {
        // 创建命名管道
        final pipeName = params.pipeName.toNativeUtf16();
        final hPipe = CreateNamedPipe(
          pipeName.cast(),
          PIPE_ACCESS_INBOUND,
          PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT,
          params.isKeyPipe ? 1 : 10,
          1024,
          1024,
          0,
          nullptr,
        );

        if (hPipe == INVALID_HANDLE_VALUE) {
          free(pipeName);
          consecutiveErrors++;
          if (consecutiveErrors >= maxConsecutiveErrors) {
            break;
          }
          sleep(Duration(seconds: params.isKeyPipe ? 2 : 1));
          continue;
        }

        // 等待客户端连接
        final connected = ConnectNamedPipe(hPipe, nullptr);
        if (connected == 0) {
          final error = GetLastError();
          if (error != ERROR_PIPE_CONNECTED) {
            CloseHandle(hPipe);
            free(pipeName);
            consecutiveErrors++;
            if (consecutiveErrors >= maxConsecutiveErrors) {
              break;
            }
            sleep(Duration(milliseconds: params.isKeyPipe ? 500 : 100));
            continue;
          }
        }

        // 读取数据
        final buffer = calloc<Uint8>(1024);
        final bytesRead = calloc<DWORD>();

        try {
          final mode = calloc<Uint32>();
          mode.value = PIPE_READMODE_MESSAGE;
          SetNamedPipeHandleState(hPipe, mode, nullptr, nullptr);
          free(mode);
          
          final readResult = ReadFile(hPipe, buffer.cast(), 1024, bytesRead, nullptr);
          
          if (readResult != 0 && bytesRead.value > 0) {
            final bytes = buffer.asTypedList(bytesRead.value);
            final data = utf8.decode(bytes, allowMalformed: true).trim();
            
            if (data.isNotEmpty) {
              params.dataSendPort.send(data);
              consecutiveErrors = 0;
            }
          }
        } finally {
          free(buffer);
          free(bytesRead);
        }

        DisconnectNamedPipe(hPipe);
        CloseHandle(hPipe);
        free(pipeName);

        sleep(Duration(milliseconds: params.isKeyPipe ? 100 : 50));

      } catch (e) {
        consecutiveErrors++;
        if (consecutiveErrors >= maxConsecutiveErrors) {
          break;
        }
        sleep(Duration(seconds: params.isKeyPipe ? 5 : 1));
      }
    }
    
    controlPort.close();
  }

}

/// Isolate 参数类
class _IsolateParams {
  final SendPort dataSendPort;
  final String pipeName;
  final bool isKeyPipe;

  _IsolateParams({
    required this.dataSendPort,
    required this.pipeName,
    required this.isKeyPipe,
  });
}
