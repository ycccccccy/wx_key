import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:async';
import 'services/dll_injector.dart';
import 'services/key_storage.dart';
import 'services/pipe_listener.dart';

void main() {
  runApp(const MyApp());
}

/// 动画提示组件
class AnimatedToast extends StatefulWidget {
  final String message;
  final Color backgroundColor;
  final IconData icon;
  final Duration duration;

  const AnimatedToast({
    super.key,
    required this.message,
    required this.backgroundColor,
    required this.icon,
    this.duration = const Duration(seconds: 3),
  });

  @override
  State<AnimatedToast> createState() => _AnimatedToastState();
}

class _AnimatedToastState extends State<AnimatedToast>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    ));

    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));

    _controller.forward();

    // 自动隐藏
    Future.delayed(widget.duration, () {
      if (mounted) {
        _hide();
      }
    });
  }

  void _hide() async {
    await _controller.reverse();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 60),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Opacity(
                  opacity: _opacityAnimation.value,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: Container(
                      constraints: const BoxConstraints(
                        maxWidth: 350,
                        minWidth: 200,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: widget.backgroundColor,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: widget.backgroundColor.withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, -8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              widget.icon,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              widget.message,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'HarmonyOS_SansSC',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 显示动画提示的全局方法
void showAnimatedToast(
  BuildContext context, {
  required String message,
  required Color backgroundColor,
  required IconData icon,
  Duration duration = const Duration(seconds: 3),
}) {
  showDialog(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    useSafeArea: false,
    builder: (context) => AnimatedToast(
      message: message,
      backgroundColor: backgroundColor,
      icon: icon,
      duration: duration,
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '微信密钥提取工具',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF07c160), 
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'HarmonyOS_SansSC',
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontFamily: 'HarmonyOS_SansSC', fontWeight: FontWeight.w700),
          displayMedium: TextStyle(fontFamily: 'HarmonyOS_SansSC', fontWeight: FontWeight.w600),
          displaySmall: TextStyle(fontFamily: 'HarmonyOS_SansSC', fontWeight: FontWeight.w500),
          headlineLarge: TextStyle(fontFamily: 'HarmonyOS_SansSC', fontWeight: FontWeight.w600),
          headlineMedium: TextStyle(fontFamily: 'HarmonyOS_SansSC', fontWeight: FontWeight.w500),
          headlineSmall: TextStyle(fontFamily: 'HarmonyOS_SansSC', fontWeight: FontWeight.w500),
          titleLarge: TextStyle(fontFamily: 'HarmonyOS_SansSC', fontWeight: FontWeight.w600),
          titleMedium: TextStyle(fontFamily: 'HarmonyOS_SansSC', fontWeight: FontWeight.w500),
          titleSmall: TextStyle(fontFamily: 'HarmonyOS_SansSC', fontWeight: FontWeight.w500),
          bodyLarge: TextStyle(fontFamily: 'HarmonyOS_SansSC', fontWeight: FontWeight.w400),
          bodyMedium: TextStyle(fontFamily: 'HarmonyOS_SansSC', fontWeight: FontWeight.w400),
          bodySmall: TextStyle(fontFamily: 'HarmonyOS_SansSC', fontWeight: FontWeight.w400),
          labelLarge: TextStyle(fontFamily: 'HarmonyOS_SansSC', fontWeight: FontWeight.w500),
          labelMedium: TextStyle(fontFamily: 'HarmonyOS_SansSC', fontWeight: FontWeight.w500),
          labelSmall: TextStyle(fontFamily: 'HarmonyOS_SansSC', fontWeight: FontWeight.w500),
        ),
      ),
      home: const MyHomePage(title: '微信密钥提取工具'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool _isWechatRunning = false;
  bool _isDllInjected = false;
  bool _isLoading = false;
  String _statusMessage = '未检测到微信进程';
  String _logFilePath = '';
  
  // 新增状态变量
  String? _extractedKey;
  String? _savedKey;
  DateTime? _keyTimestamp;
  
  // 版本和DLL相关
  String? _wechatVersion;
  
  // 日志相关
  final List<Map<String, String>> _logMessages = [];
  final int _maxLogMessages = 10;

  @override
  void initState() {
    super.initState();
    _initLogPath();
    _loadSavedData();
    _checkWechatStatus();
    _detectWeChatVersion();
    _startStatusPolling();
  }

  @override
  void dispose() {
    // 确保释放所有资源
    _backupMonitorTimer?.cancel();
    PipeListener.stopListening();
    super.dispose();
  }

  Future<void> _initLogPath() async {
    try {
      final userProfile = Platform.environment['USERPROFILE'] ?? 'C:\\Users\\cc';
      final logPath = path.join(userProfile, 'Documents', 'WechatKeyHunter_Log.txt');
      
      setState(() {
        _logFilePath = logPath;
      });
      
    } catch (e) {
      setState(() {
        _logFilePath = 'C:\\Users\\cc\\Documents\\WechatKeyHunter_Log.txt';
      });
    }
  }

  /// 加载保存的数据
  Future<void> _loadSavedData() async {
    try {
      // 加载保存的密钥信息
      final keyInfo = await KeyStorage.getKeyInfo();
      if (keyInfo != null) {
        setState(() {
          _savedKey = keyInfo['key'] as String;
          _keyTimestamp = keyInfo['timestamp'] as DateTime?;
        });
      }
    } catch (e) {
    }
  }

  /// 检测微信版本
  Future<void> _detectWeChatVersion() async {
    try {
      final version = DllInjector.getWeChatVersion();
      if (version != null) {
        setState(() {
          _wechatVersion = version;
          _statusMessage = '检测到微信版本: $version';
        });
      } else {
        setState(() {
          _statusMessage = '未找到微信安装目录';
        });
        _showAnimatedToast('未找到微信安装目录，请检查安装路径', Colors.red, Icons.error);
      }
    } catch (e) {
    }
  }

  /// 启动命名管道监听
  Future<void> _startPipeListener() async {
    try {
      final success = await PipeListener.startListening();

      if (success) {
        // 监听密钥流
        PipeListener.keyStream.listen((key) {
          _onKeyReceived(key);
        });
        
        // 监听日志流
        PipeListener.logStream.listen((log) {
          _addLogMessage(log['type']!, log['message']!);
        });
        
      } else {
      }
      
      // 启动备份文件监控（以防管道通信失败）
      _startBackupFileMonitoring();
    } catch (e) {
    }
  }
  
  /// 添加日志消息
  void _addLogMessage(String type, String message) {
    setState(() {
      _logMessages.insert(0, {'type': type, 'message': message});
      if (_logMessages.length > _maxLogMessages) {
        _logMessages.removeLast();
      }
      
      // 根据类型更新状态消息
      if (type == 'INFO' || type == 'SUCCESS') {
        _statusMessage = message;
      }
    });
    
    // 显示重要消息的Toast
    if (type == 'SUCCESS') {
      _showAnimatedToast(message, Colors.green, Icons.check_circle);
    } else if (type == 'ERROR') {
      _showAnimatedToast(message, Colors.red, Icons.error);
    } else if (type == 'WARNING') {
      _showAnimatedToast(message, Colors.orange, Icons.warning);
    }
  }

  /// 监控备份文件
  Timer? _backupMonitorTimer;
  
  void _startBackupFileMonitoring() {
    _backupMonitorTimer?.cancel(); // 取消之前的定时器
    _backupMonitorTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      try {
        // 如果已经获取到密钥或没有注入，停止监控
        if (_extractedKey != null || !_isDllInjected) {
          timer.cancel();
          return;
        }
        
        final backupFile = File(r'C:\temp\wechat_key_backup.txt');
        if (await backupFile.exists()) {
          final content = await backupFile.readAsString();
          if (content.trim().isNotEmpty && _extractedKey == null) {
            _onKeyReceived(content.trim());
            // 删除备份文件，避免重复读取
            await backupFile.delete();
            timer.cancel(); // 停止监控
          }
        }
      } catch (e) {
        // 忽略文件监控错误
      }
    });
  }

  /// 处理接收到的密钥
  Future<void> _onKeyReceived(String key) async {
    try {
      
      setState(() {
        _extractedKey = key;
      });

      // 自动保存密钥
      final success = await KeyStorage.saveKey(key);
      if (success) {
        setState(() {
          _savedKey = key;
          _keyTimestamp = DateTime.now();
          _statusMessage = '密钥获取成功！';
        });
        _showAnimatedToast('密钥已自动保存', Colors.green, Icons.check_circle);
        
        // 密钥获取成功后，停止管道监听以释放资源
        _stopPipeListenerDelayed();
      } else {
        _showAnimatedToast('密钥保存失败', Colors.red, Icons.error);
      }
    } catch (e) {
    }
  }

  /// 延迟停止管道监听
  Future<void> _stopPipeListenerDelayed() async {
    // 等待3秒，确保所有消息都已接收
    await Future.delayed(const Duration(seconds: 3));
    await PipeListener.stopListening();
  }

  /// 启动密钥获取超时计时器
  void _startKeyTimeout() {
    // 60秒后如果还没有获取到密钥，停止监听
    Future.delayed(const Duration(seconds: 60), () async {
      if (mounted && _extractedKey == null && _isDllInjected) {
        await PipeListener.stopListening();
        setState(() {
          _statusMessage = '密钥获取超时，请重新尝试';
        });
      }
    });
  }

  /// 自动化注入流程：下载DLL -> 关闭微信 -> 启动微信 -> 等待窗口 -> 注入
  Future<void> _autoInjectDll() async {
    if (_wechatVersion == null) {
      _showAnimatedToast('未检测到微信版本', Colors.red, Icons.error);
      return;
    }

    // 启动管道监听
    await _startPipeListener();

    setState(() {
      _isLoading = true;
      _statusMessage = '准备开始自动注入...';
    });

    try {
      // 1. 下载DLL
      setState(() {
        _statusMessage = '正在从GitHub下载DLL文件';
      });

      final dllPath = await DllInjector.downloadDll(_wechatVersion!);
      if (dllPath == null) {
        _showAnimatedToast('DLL下载失败，请检查网络连接', Colors.red, Icons.error);
        setState(() {
          _isLoading = false;
          _statusMessage = 'DLL下载失败';
        });
        return;
      }

      _showAnimatedToast('DLL下载成功', Colors.green, Icons.check_circle);

      // 2. 检查微信是否运行，如果运行则请求用户确认关闭
      if (_isWechatRunning) {
        setState(() {
          _isLoading = false;
        });
        
        final shouldClose = await _showConfirmDialog(
          title: '确认关闭微信',
          content: '检测到微信正在运行，需要重启微信才能注入DLL。\n是否关闭当前微信？',
          confirmText: '关闭并继续',
          cancelText: '取消',
        );
        
        if (!shouldClose) {
          setState(() {
            _statusMessage = '用户取消操作';
          });
          // 用户取消，停止管道监听
          await PipeListener.stopListening();
          return;
        }
        
        setState(() {
          _isLoading = true;
          _statusMessage = '正在关闭现有微信进程...';
        });
        
        DllInjector.killWeChatProcesses();
        await Future.delayed(const Duration(seconds: 2));
        _showAnimatedToast('已关闭现有微信进程', Colors.green, Icons.info);
      }

      // 3. 启动微信
      setState(() {
        _statusMessage = '正在启动微信...';
      });

      final launched = await DllInjector.launchWeChat();
      if (!launched) {
        _showAnimatedToast('微信启动失败', Colors.red, Icons.error);
        setState(() {
          _isLoading = false;
          _statusMessage = '微信启动失败';
        });
        return;
      }

      _showAnimatedToast('微信启动成功', Colors.green, Icons.check_circle);

      // 4. 等待微信窗口出现
      setState(() {
        _statusMessage = '等待微信窗口出现...';
      });

      final windowAppeared = await DllInjector.waitForWeChatWindow(maxWaitSeconds: 15);
      if (!windowAppeared) {
        _showAnimatedToast('等待微信窗口超时', Colors.orange, Icons.warning);
        setState(() {
          _isLoading = false;
          _statusMessage = '等待微信窗口超时';
        });
        return;
      }

      // 5. 延迟几秒，等待微信完全初始化
      setState(() {
        _statusMessage = '等待微信完全启动...';
      });
      for (int i = 5; i > 0; i--) {
        setState(() {
          _statusMessage = '等待微信完全启动... ($i秒)';
        });
        await Future.delayed(const Duration(seconds: 1));
      }

      // 6. 注入DLL
      setState(() {
        _statusMessage = '正在注入DLL...';
      });

      final success = DllInjector.injectDll('Weixin.exe', dllPath);
      
      if (success) {
        setState(() {
          _isDllInjected = true;
          _statusMessage = 'DLL注入成功！等待密钥获取...';
        });
        _showAnimatedToast('DLL注入成功！', Colors.green, Icons.check_circle);
        
        // 注入成功后，清理DLL文件
        _cleanupDllFile(dllPath);
        
        // 设置超时，如果一段时间内没有收到密钥，则停止监听
        _startKeyTimeout();
      } else {
        _showAnimatedToast('DLL注入失败！请确保以管理员身份运行', Colors.red, Icons.error);
        setState(() {
          _statusMessage = 'DLL注入失败';
        });
        // 注入失败也清理DLL
        _cleanupDllFile(dllPath);
        // 停止管道监听
        await PipeListener.stopListening();
      }
    } catch (e) {
      _showAnimatedToast('自动注入过程出错: $e', Colors.red, Icons.error);
      setState(() {
        _statusMessage = '自动注入失败: $e';
      });
      // 出错时停止管道监听
      await PipeListener.stopListening();
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 清理下载的DLL文件
  Future<void> _cleanupDllFile(String dllPath) async {
    try {
      await Future.delayed(const Duration(seconds: 2)); // 等待DLL加载到内存
      final dllFile = File(dllPath);
      if (await dllFile.exists()) {
        await dllFile.delete();
      }
    } catch (e) {
    }
  }

  /// 复制密钥到剪贴板
  Future<void> _copyKeyToClipboard(String key) async {
    try {
      await Clipboard.setData(ClipboardData(text: key));
      _showAnimatedToast('密钥已复制到剪贴板', Colors.green, Icons.copy);
    } catch (e) {
      _showAnimatedToast('复制失败: $e', Colors.red, Icons.error);
    }
  }




  // 定期检查微信状态
  void _startStatusPolling() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _checkWechatStatus();
        _startStatusPolling();
      }
    });
  }

  Future<void> _checkWechatStatus() async {
    final isRunning = DllInjector.isProcessRunning('Weixin.exe');
    if (mounted) {
      setState(() {
        _isWechatRunning = isRunning;
        if (!_isLoading) {
        if (isRunning) {
            if (!_isDllInjected) {
              _statusMessage = _wechatVersion != null 
                  ? '检测到微信进程 (版本: $_wechatVersion)'
                  : '检测到微信进程';
          } else {
            _statusMessage = 'DLL已注入，正在监听密钥';
          }
        } else {
            _statusMessage = _wechatVersion != null 
                ? '未检测到微信进程 (检测到版本: $_wechatVersion)'
                : '未检测到微信进程';
          _isDllInjected = false;
        }
        }
      });
    }
  }




  void _showAnimatedToast(String message, Color backgroundColor, IconData icon) {
    showAnimatedToast(
      context,
      message: message,
      backgroundColor: backgroundColor,
      icon: icon,
    );
  }

  /// 显示确认对话框
  Future<bool> _showConfirmDialog({
    required String title,
    required String content,
    required String confirmText,
    required String cancelText,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'HarmonyOS_SansSC',
                ),
              ),
            ],
          ),
          content: Text(
            content,
            style: const TextStyle(
              fontSize: 14,
              fontFamily: 'HarmonyOS_SansSC',
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                cancelText,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'HarmonyOS_SansSC',
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF07c160),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: Text(
                confirmText,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontFamily: 'HarmonyOS_SansSC',
                ),
              ),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Widget _buildSimpleActionButton() {
    final isEnabled = !_isLoading && _wechatVersion != null;
    
    return Container(
      width: double.infinity,
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: isEnabled ? [
          BoxShadow(
            color: const Color(0xFF07c160).withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ] : null,
      ),
      child: ElevatedButton(
        onPressed: isEnabled ? _autoInjectDll : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF07c160),
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade200,
          disabledForegroundColor: Colors.grey.shade400,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                '开始提取密钥',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'HarmonyOS_SansSC',
                  letterSpacing: 0.3,
                ),
              ),
      ),
    );
  }

  Widget _buildSimpleKeyCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF07c160).withOpacity(0.15),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF07c160).withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '密钥',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                  fontFamily: 'HarmonyOS_SansSC',
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _copyKeyToClipboard(_savedKey!),
                icon: const Icon(Icons.content_copy_rounded, size: 15, color: Color(0xFF07c160)),
                label: const Text(
                  '复制',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF07c160),
                    fontFamily: 'HarmonyOS_SansSC',
                    fontWeight: FontWeight.w500,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  backgroundColor: const Color(0xFF07c160).withOpacity(0.08),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(
              _savedKey!,
              style: const TextStyle(
                fontSize: 13,
                fontFamily: 'HarmonyOS_SansSC',
                color: Colors.black87,
                height: 1.6,
                letterSpacing: 0.5,
              ),
            ),
          ),
          if (_keyTimestamp != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.access_time_rounded,
                  size: 14,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 6),
                Text(
                  '获取时间: ${_keyTimestamp!.toString().substring(0, 19)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontFamily: 'HarmonyOS_SansSC',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLogItem(Map<String, String> log) {
    Color iconColor;
    IconData icon;
    
    switch (log['type']) {
      case 'SUCCESS':
        iconColor = const Color(0xFF07c160);
        icon = Icons.check_circle_rounded;
        break;
      case 'ERROR':
        iconColor = Colors.red.shade400;
        icon = Icons.error_rounded;
        break;
      case 'WARNING':
        iconColor = Colors.orange.shade400;
        icon = Icons.warning_amber_rounded;
        break;
      default:
        iconColor = Colors.blue.shade400;
        icon = Icons.info_rounded;
    }
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              log['message']!,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                fontFamily: 'HarmonyOS_SansSC',
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 柔和标题栏
            Container(
              padding: const EdgeInsets.fromLTRB(32, 32, 32, 28),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '微信密钥提取工具',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade900,
                      fontFamily: 'HarmonyOS_SansSC',
                      letterSpacing: 0.2,
                      height: 1.2,
                    ),
                  ),
                  if (_wechatVersion != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF07c160).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '微信版本 $_wechatVersion',
                        style: TextStyle(
                          fontSize: 13,
                          color: const Color(0xFF07c160).withOpacity(0.9),
                          fontFamily: 'HarmonyOS_SansSC',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // 主内容区域
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 当前状态
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.grey.shade100,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          if (_isLoading)
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: const Color(0xFF07c160).withOpacity(0.8),
                              ),
                            )
                          else
                            Icon(
                              _isDllInjected ? Icons.check_circle_rounded : Icons.circle_outlined,
                              color: _isDllInjected ? const Color(0xFF07c160) : Colors.grey.shade400,
                              size: 18,
                            ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              _statusMessage,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade700,
                                fontFamily: 'HarmonyOS_SansSC',
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // 操作按钮
                    if (!_isDllInjected)
                      _buildSimpleActionButton(),
                    const SizedBox(height: 32),
                    
                    // 密钥显示
                    if (_savedKey != null) ...[
                      _buildSimpleKeyCard(),
                      const SizedBox(height: 28),
                    ],
                    
                    // 日志消息
                    if (_logMessages.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 12),
                        child: Text(
                          '运行日志',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade800,
                            fontFamily: 'HarmonyOS_SansSC',
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.grey.shade100,
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: _logMessages.take(8).map((log) => _buildLogItem(log)).toList(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
