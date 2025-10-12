import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// 命名管道监听服务
/// 监听DLL发送的微信数据库密钥
class PipeListener {
  static const String _pipeName = r'\\.\pipe\WeChatKeyPipe';
  static bool _isListening = false;
  static StreamController<String>? _keyController;
  static Isolate? _listenerIsolate;
  static SendPort? _sendPort;

  /// 获取密钥流
  /// 当收到密钥时会触发此流
  static Stream<String> get keyStream {
    _keyController ??= StreamController<String>.broadcast();
    return _keyController!.stream;
  }

  /// 开始监听命名管道
  /// 返回是否成功启动监听
  static Future<bool> startListening() async {
    if (_isListening) {
      print('[PipeListener] 已经在监听中');
      return true;
    }

    try {
      // 创建接收端口
      final receivePort = ReceivePort();
      _sendPort = receivePort.sendPort;

      // 启动监听隔离
      _listenerIsolate = await Isolate.spawn(
        _pipeListenerIsolate,
        _sendPort!,
      );

      // 监听来自隔离的消息
      receivePort.listen((message) {
        print('[PipeListener] 收到消息类型: ${message.runtimeType}');
        if (message is String) {
          // 收到密钥数据
          print('[PipeListener] 收到密钥数据: ${message.length} 字符');
          print('[PipeListener] 密钥内容: ${message.length > 0 ? message.substring(0, message.length > 20 ? 20 : message.length) : "空"}');
          _keyController?.add(message);
          print('[PipeListener] 密钥已添加到流控制器');
        } else if (message is Map<String, dynamic>) {
          // 收到状态消息
          final status = message['status'] as String;
          final error = message['error'] as String?;
          print('[PipeListener] 状态消息: $status${error != null ? ': $error' : ''}');
        } else {
          print('[PipeListener] 未知消息类型: ${message.runtimeType}');
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
      _listenerIsolate?.kill();
      _listenerIsolate = null;
      _sendPort = null;
      _isListening = false;
      await _keyController?.close();
      _keyController = null;
      print('[PipeListener] 命名管道监听已停止');
    } catch (e) {
      print('[PipeListener] 停止监听失败: $e');
    }
  }

  /// 检查是否正在监听
  static bool get isListening => _isListening;


  /// 命名管道监听隔离函数
  static void _pipeListenerIsolate(SendPort sendPort) {
    print('[PipeListener] 隔离线程启动');

    while (true) {
      try {
        // 创建命名管道
        final pipeName = _pipeName.toNativeUtf16();
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
          final error = GetLastError();
          sendPort.send({
            'status': '创建命名管道失败',
            'error': '错误代码: $error, 管道名称: $_pipeName'
          });
          free(pipeName);
          sleep(const Duration(seconds: 2)); // 减少等待时间
          continue;
        }

        sendPort.send({'status': '命名管道创建成功，等待连接...'});

        // 等待客户端连接 - 使用阻塞模式
        final connected = ConnectNamedPipe(hPipe, nullptr);
        if (connected == 0) {
          final error = GetLastError();
          if (error != ERROR_PIPE_CONNECTED) {
            sendPort.send({
              'status': '等待客户端连接失败',
              'error': '错误代码: $error'
            });
            CloseHandle(hPipe);
            free(pipeName);
            sleep(const Duration(milliseconds: 500)); // 增加等待时间
            continue;
          }
        }

        sendPort.send({'status': '客户端已连接，等待数据...'});

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
          sendPort.send({'status': 'ReadFile结果: $readResult, 读取字节数: ${bytesRead.value}'});
          
          if (readResult != 0) {
            final data = String.fromCharCodes(
              buffer.asTypedList(bytesRead.value).takeWhile((c) => c != 0)
            );
            
            sendPort.send({'status': '原始数据长度: ${data.length}, 内容: ${data.length > 0 ? data.substring(0, data.length > 20 ? 20 : data.length) : "空"}'});
            
            if (data.isNotEmpty) {
              sendPort.send(data);
              sendPort.send({'status': '密钥数据已接收: ${data.substring(0, data.length > 8 ? 8 : data.length)}...'});
            } else {
              sendPort.send({'status': '接收到空数据'});
            }
          } else {
            final error = GetLastError();
            sendPort.send({
              'status': '读取数据失败',
              'error': '错误代码: $error'
            });
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
        sendPort.send({
          'status': '管道监听异常',
          'error': e.toString()
        });
        sleep(const Duration(seconds: 5));
      }
    }
  }
}
