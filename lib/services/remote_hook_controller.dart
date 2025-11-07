import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:async';
import 'package:ffi/ffi.dart';
import 'app_logger.dart';

// DLL导出函数类型定义
typedef InitializeHookNative = Bool Function(Uint32 targetPid);
typedef InitializeHookDart = bool Function(int targetPid);

typedef PollKeyDataNative = Bool Function(Pointer<Utf8> keyBuffer, Int32 bufferSize);
typedef PollKeyDataDart = bool Function(Pointer<Utf8> keyBuffer, int bufferSize);

typedef GetStatusMessageNative = Bool Function(
  Pointer<Utf8> statusBuffer,
  Int32 bufferSize,
  Pointer<Int32> outLevel,
);
typedef GetStatusMessageDart = bool Function(
  Pointer<Utf8> statusBuffer,
  int bufferSize,
  Pointer<Int32> outLevel,
);

typedef CleanupHookNative = Bool Function();
typedef CleanupHookDart = bool Function();

typedef GetLastErrorMsgNative = Pointer<Utf8> Function();
typedef GetLastErrorMsgDart = Pointer<Utf8> Function();

/// 远程Hook控制器（轮询模式 - 无FFI回调）
/// 新架构：控制器DLL运行在Flutter进程中，使用远程内存操作Hook目标进程
class RemoteHookController {
  static DynamicLibrary? _dll;
  static InitializeHookDart? _initializeHook;
  static PollKeyDataDart? _pollKeyData;
  static GetStatusMessageDart? _getStatusMessage;
  static CleanupHookDart? _cleanupHook;
  static GetLastErrorMsgDart? _getLastErrorMsg;
  
  static Timer? _pollingTimer;
  static Function(String)? _onKeyReceived;
  static Function(String, int)? _onStatus;
  
  /// 初始化DLL
  static bool initialize(String dllPath) {
    try {
      AppLogger.info('加载控制器DLL: $dllPath');
      
      if (!File(dllPath).existsSync()) {
        AppLogger.error('DLL文件不存在: $dllPath');
        return false;
      }
      
      // 加载DLL到当前进程（Flutter进程）
      _dll = DynamicLibrary.open(dllPath);
      AppLogger.success('DLL加载成功');
      
      // 查找导出函数
      _initializeHook = _dll!.lookupFunction<InitializeHookNative, InitializeHookDart>(
        'InitializeHook',
      );
      
      _pollKeyData = _dll!.lookupFunction<PollKeyDataNative, PollKeyDataDart>(
        'PollKeyData',
      );
      
      _getStatusMessage = _dll!.lookupFunction<GetStatusMessageNative, GetStatusMessageDart>(
        'GetStatusMessage',
      );
      
      _cleanupHook = _dll!.lookupFunction<CleanupHookNative, CleanupHookDart>(
        'CleanupHook',
      );
      
      _getLastErrorMsg = _dll!.lookupFunction<GetLastErrorMsgNative, GetLastErrorMsgDart>(
        'GetLastErrorMsg',
      );
      
      AppLogger.success('所有导出函数加载成功');
      return true;
    } catch (e) {
      AppLogger.error('初始化DLL失败: $e');
      return false;
    }
  }
  
  /// 安装Hook到目标进程（轮询模式）
  /// @param targetPid 目标进程PID（微信进程）
  /// @param onKeyReceived 密钥接收回调
  /// @param onStatus 状态回调
  static bool installHook({
    required int targetPid,
    required Function(String) onKeyReceived,
    Function(String, int)? onStatus,
  }) {
    try {
      if (_dll == null || _initializeHook == null) {
        AppLogger.error('DLL未初始化，请先调用initialize()');
        return false;
      }
      
      AppLogger.info('开始安装远程Hook，目标PID: $targetPid');
      
      // 保存回调函数引用
      _onKeyReceived = onKeyReceived;
      _onStatus = onStatus;
      
      // 调用DLL的InitializeHook函数（无回调参数）
      final success = _initializeHook!(targetPid);
      
      if (success) {
        AppLogger.success('远程Hook安装成功');
        
        // 启动轮询定时器（每100ms检查一次）
        _startPolling();
      } else {
        final error = getLastErrorMessage();
        AppLogger.error('远程Hook安装失败: $error');
      }
      
      return success;
    } catch (e) {
      AppLogger.error('安装Hook异常: $e');
      return false;
    }
  }
  
  /// 启动轮询定时器
  static void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _pollData();
    });
    AppLogger.info('已启动轮询定时器');
  }
  
  /// 停止轮询
  static void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    AppLogger.info('已停止轮询定时器');
  }
  
  /// 轮询数据
  static void _pollData() {
    if (_pollKeyData == null || _getStatusMessage == null) {
      return;
    }
    
    try {
      // 检查密钥数据
      final keyBuffer = calloc<Uint8>(65);
      try {
        if (_pollKeyData!(keyBuffer.cast<Utf8>(), 65)) {
          final keyString = _decodeUtf8String(keyBuffer, 65);
          AppLogger.success('轮询到密钥数据: $keyString');
          
          if (_onKeyReceived != null) {
            _onKeyReceived!(keyString);
          }
        }
      } finally {
        calloc.free(keyBuffer);
      }
      
      // 检查状态消息（一次最多处理5条）
      for (int i = 0; i < 5; i++) {
        final statusBuffer = calloc<Uint8>(256);
        final levelPtr = calloc<Int32>();
        
        try {
          if (_getStatusMessage!(statusBuffer.cast<Utf8>(), 256, levelPtr)) {
            final statusString = _decodeUtf8String(statusBuffer, 256);
            final level = levelPtr.value;
            
            switch (level) {
              case 0:
                AppLogger.info('[DLL] $statusString');
                break;
              case 1:
                AppLogger.success('[DLL] $statusString');
                break;
              case 2:
                AppLogger.error('[DLL] $statusString');
                break;
            }
            
            if (_onStatus != null) {
              _onStatus!(statusString, level);
            }
          } else {
            break; // 没有更多状态消息
          }
        } finally {
          calloc.free(statusBuffer);
          calloc.free(levelPtr);
        }
      }
    } catch (e) {
      AppLogger.error('轮询数据异常: $e');
    }
  }
  
  /// 卸载Hook
  static bool uninstallHook() {
    try {
      // 先停止轮询
      _stopPolling();
      
      if (_dll == null || _cleanupHook == null) {
        AppLogger.warning('DLL未初始化');
        return false;
      }
      
      AppLogger.info('开始卸载Hook');
      final success = _cleanupHook!();
      
      if (success) {
        AppLogger.success('Hook卸载成功');
      } else {
        AppLogger.error('Hook卸载失败');
      }
      
      // 清理回调引用
      _onKeyReceived = null;
      _onStatus = null;
      
      return success;
    } catch (e) {
      AppLogger.error('卸载Hook异常: $e');
      return false;
    }
  }
  
  /// 获取最后一次错误信息
  static String getLastErrorMessage() {
    try {
      if (_dll == null || _getLastErrorMsg == null) {
        return '未知错误';
      }
      
      final errorPtr = _getLastErrorMsg!();
      if (errorPtr == nullptr) {
        return '无错误';
      }
      
      return _decodeUtf8String(errorPtr.cast<Uint8>(), 512);
    } catch (e) {
      return '获取错误信息失败: $e';
    }
  }
  
  /// 清理资源
  static void dispose() {
    uninstallHook();
    _dll = null;
    _initializeHook = null;
    _pollKeyData = null;
    _getStatusMessage = null;
    _cleanupHook = null;
    _getLastErrorMsg = null;
  }

  static String _decodeUtf8String(Pointer<Uint8> buffer, int maxLength) {
    if (buffer == nullptr) return '';
    final bytes = <int>[];
    for (var i = 0; i < maxLength; i++) {
      final value = buffer.elementAt(i).value;
      if (value == 0) break;
      bytes.add(value);
    }
    if (bytes.isEmpty) return '';
    return const Utf8Decoder(allowMalformed: true).convert(bytes);
  }
}
