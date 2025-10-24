import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:async';
import 'services/dll_injector.dart';
import 'services/key_storage.dart';
import 'services/log_reader.dart';
import 'services/app_logger.dart';
import 'services/image_key_service.dart';
import 'widgets/settings_dialog.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  
  // 初始化应用日志
  await AppLogger.init();
  
  // 设置窗口选项，防止默认关闭行为
  WindowOptions windowOptions = const WindowOptions(
    center: true,
    skipTaskbar: false,
  );
  
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  
  runApp(const MyApp());
}

/// 显示动画提示的全局方法
void showAnimatedToast(
  BuildContext context, {
  required String message,
  required Color backgroundColor,
  required IconData icon,
  Duration duration = const Duration(seconds: 3),
}) {
  final overlay = Overlay.of(context);
  late OverlayEntry overlayEntry;
  
  // 创建动画控制器
  final animationController = AnimationController(
    duration: const Duration(milliseconds: 300),
    vsync: overlay,
  );

  final scaleAnimation = Tween<double>(
    begin: 0.8,
    end: 1.0,
  ).animate(CurvedAnimation(
    parent: animationController,
    curve: Curves.elasticOut,
  ));

  final opacityAnimation = Tween<double>(
    begin: 0.0,
    end: 1.0,
  ).animate(CurvedAnimation(
    parent: animationController,
    curve: Curves.easeOut,
  ));

  final slideAnimation = Tween<Offset>(
    begin: const Offset(0, 1),
    end: Offset.zero,
  ).animate(CurvedAnimation(
    parent: animationController,
    curve: Curves.easeOutBack,
  ));

  // 创建 overlay entry
  overlayEntry = OverlayEntry(
    builder: (context) => Positioned(
      bottom: 60,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: AnimatedBuilder(
              animation: animationController,
              builder: (context, child) {
                return Transform.scale(
                  scale: scaleAnimation.value,
                  child: Opacity(
                    opacity: opacityAnimation.value,
                    child: SlideTransition(
                      position: slideAnimation,
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
                          color: backgroundColor,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: backgroundColor.withOpacity(0.3),
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
                                icon,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                message,
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
      ),
    ),
  );

  // 插入 overlay
  overlay.insert(overlayEntry);
  
  // 播放动画
  animationController.forward();

  // 自动隐藏
  Future.delayed(duration, () async {
    await animationController.reverse();
    overlayEntry.remove();
    animationController.dispose();
  });
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

class _MyHomePageState extends State<MyHomePage> with WindowListener {
  bool _isWechatRunning = false;
  bool _isDllInjected = false;
  bool _isLoading = false;
  String _statusMessage = '未检测到微信进程';
  
  // 新增状态变量
  String? _extractedKey;
  String? _savedKey;
  DateTime? _keyTimestamp;
  
  // 图片密钥相关
  int? _imageXorKey;
  String? _imageAesKey;
  DateTime? _imageKeyTimestamp;
  bool _isGettingImageKey = false;
  
  // 版本和DLL相关
  String? _wechatVersion;
  
  // 日志相关
  final List<Map<String, String>> _logMessages = [];
  final int _maxLogMessages = 10;
  
  // 控制状态轮询
  bool _isPolling = false;
  
  // 日志流订阅
  StreamSubscription<Map<String, dynamic>>? _logStreamSubscription;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // 防止默认关闭行为，让我们可以自定义关闭逻辑
    windowManager.setPreventClose(true);
    _isPolling = true;
    _loadSavedData();
    _checkWechatStatus();
    _detectWeChatVersion();
    _startStatusPolling();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    // 阻止默认关闭行为，先清理资源
    await windowManager.hide();
    // 窗口关闭时清理所有资源
    await _cleanupResources();
    // 关闭日志服务
    await AppLogger.close();
    // 等待一段时间确保所有资源都被释放
    await Future.delayed(const Duration(milliseconds: 500));
    // 销毁窗口并退出进程
    await windowManager.destroy();
    exit(0);
  }

  /// 清理所有资源
  Future<void> _cleanupResources() async {
    print('[清理] 开始清理资源...');
    
    // 停止状态轮询
    _isPolling = false;
    print('[清理] 状态轮询已停止');
    
    // 取消日志流订阅
    await _logStreamSubscription?.cancel();
    _logStreamSubscription = null;
    print('[清理] 日志流订阅已取消');
    
    // 等待一小段时间确保完全退出
    await Future.delayed(const Duration(milliseconds: 300));
    print('[清理] 资源清理完成');
  }

  /// 加载保存的数据
  Future<void> _loadSavedData() async {
    try {
      // 加载保存的数据库密钥信息
      final keyInfo = await KeyStorage.getKeyInfo();
      if (keyInfo != null) {
        setState(() {
          _savedKey = keyInfo['key'] as String;
          _keyTimestamp = keyInfo['timestamp'] as DateTime?;
        });
        await AppLogger.info('成功加载已保存的数据库密钥信息');
      }
      
      // 加载保存的图片密钥信息
      final imageKeyInfo = await KeyStorage.getImageKeyInfo();
      if (imageKeyInfo != null) {
        setState(() {
          _imageXorKey = imageKeyInfo['xorKey'] as int;
          _imageAesKey = imageKeyInfo['aesKey'] as String;
          _imageKeyTimestamp = imageKeyInfo['timestamp'] as DateTime?;
        });
        await AppLogger.info('成功加载已保存的图片密钥信息');
      }
    } catch (e, stackTrace) {
      await AppLogger.error('加载保存的数据失败', e, stackTrace);
    }
  }

  /// 检测微信版本
  Future<void> _detectWeChatVersion() async {
    try {
      final version = await DllInjector.getWeChatVersion();
      if (version != null) {
        setState(() {
          _wechatVersion = version;
          _statusMessage = '检测到微信版本: $version';
        });
        await AppLogger.success('检测到微信版本: $version');
      } else {
        setState(() {
          _statusMessage = '未找到微信安装目录';
        });
        await AppLogger.warning('未找到微信安装目录');
        _showAnimatedToast('未找到微信安装目录', Colors.orange, Icons.warning);
        // 延迟打开设置页面让用户手动选择
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _openSettings();
          }
        });
      }
    } catch (e, stackTrace) {
      await AppLogger.error('检测微信版本失败', e, stackTrace);
    }
  }

  /// 启动日志文件监控
  Future<void> _startLogMonitoring() async {
    try {
      // 清空日志文件
      await LogReader.clearLog();
      await AppLogger.info('已清空DLL日志文件，开始监控');
      
      // 创建日志轮询流并监听
      _logStreamSubscription = LogReader.createPollingStream().listen((event) {
        if (event['type'] == 'key') {
          // 收到密钥
          _onKeyReceived(event['data'] as String);
        } else if (event['type'] == 'log') {
          // 收到日志消息
          final logData = event['data'] as Map<String, String>;
          _addLogMessage(logData['type']!, logData['message']!);
        }
      });
      
    } catch (e, stackTrace) {
      await AppLogger.error('启动日志监控失败', e, stackTrace);
      print('[日志监控] 启动失败: $e');
    }
  }
  
  /// 添加日志消息
  void _addLogMessage(String type, String message) {
    setState(() {
      _logMessages.insert(0, {'type': type, 'message': message});
      if (_logMessages.length > _maxLogMessages) {
        _logMessages.removeLast();
      }
      
      // 根据类型更新状态消息（但如果已经获取到密钥，保持"密钥获取成功"状态）
      if ((type == 'INFO' || type == 'SUCCESS') && _extractedKey == null) {
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


  /// 处理接收到的密钥
  Future<void> _onKeyReceived(String key) async {
    try {
      await AppLogger.success('成功接收到密钥: ${key.substring(0, 8)}...');
      
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
        await AppLogger.success('密钥已自动保存');
        _showAnimatedToast('密钥已自动保存', Colors.green, Icons.check_circle);
        
        // 密钥获取成功后，延迟停止日志监控以释放资源
        Future.delayed(const Duration(seconds: 3), () async {
          if (mounted) {
            await _cleanupResources();
          }
        });
      } else {
        await AppLogger.error('密钥保存失败');
        _showAnimatedToast('密钥保存失败', Colors.red, Icons.error);
      }
    } catch (e, stackTrace) {
      await AppLogger.error('处理接收到的密钥时出错', e, stackTrace);
    }
  }

  /// 启动密钥获取超时计时器
  void _startKeyTimeout() {
    // 60秒后如果还没有获取到密钥，停止监听
    Future.delayed(const Duration(seconds: 60), () async {
      if (mounted && _extractedKey == null && _isDllInjected) {
        await _cleanupResources();
        setState(() {
          _statusMessage = '密钥获取超时，请重新尝试';
        });
      }
    });
  }

  /// 自动化注入流程：下载DLL -> 关闭微信 -> 启动微信 -> 等待窗口 -> 注入
  Future<void> _autoInjectDll() async {
    if (_wechatVersion == null) {
      _addLogMessage('ERROR', '未检测到微信版本');
      await AppLogger.error('未检测到微信版本，无法开始注入');
      return;
    }

    // 清除之前的提取状态，允许重新提取
    setState(() {
      _extractedKey = null;
      _isStoppingListener = false;
    });

    // 启动日志监控
    await _startLogMonitoring();

    setState(() {
      _isLoading = true;
      _statusMessage = '准备开始自动注入...';
    });
    _addLogMessage('INFO', '准备开始自动注入...');
    await AppLogger.info('用户开始自动注入流程，微信版本: $_wechatVersion');

    try {
      // 1. 下载DLL
      _addLogMessage('INFO', '正在从GitHub下载DLL文件');
      setState(() {
        _statusMessage = '正在从GitHub下载DLL文件';
      });
      await AppLogger.info('开始下载DLL文件，版本: $_wechatVersion');

      final downloadResult = await DllInjector.downloadDll(_wechatVersion!);
      if (!downloadResult.success) {
        // 下载失败，根据错误类型处理
        if (downloadResult.error == DllDownloadError.networkError) {
          _addLogMessage('ERROR', '网络连接失败，无法下载DLL文件');
          await AppLogger.error('网络连接失败: $_wechatVersion');
          setState(() {
            _isLoading = false;
            _statusMessage = '网络连接失败';
          });
          // 停止日志监控并清理资源
          await _cleanupResources();
          // 显示网络错误弹窗，提供手动选择DLL选项
          _showNetworkErrorDialog();
          return;
        } else if (downloadResult.error == DllDownloadError.versionNotFound) {
          _addLogMessage('ERROR', '版本未适配');
          await AppLogger.error('版本未适配: $_wechatVersion，GitHub上没有对应的DLL文件');
          setState(() {
            _isLoading = false;
            _statusMessage = '版本未适配';
          });
          // 停止日志监控并清理资源
          await _cleanupResources();
          // 比较版本，显示不同的提示
          final versionComparison = await DllInjector.compareWithLatestVersion(_wechatVersion!);
          _showVersionNotSupportedDialog(versionComparison);
          return;
        } else {
          // 文件系统错误或其他错误
          _addLogMessage('ERROR', 'DLL文件处理失败');
          await AppLogger.error('DLL文件处理失败: $_wechatVersion');
          setState(() {
            _isLoading = false;
            _statusMessage = 'DLL文件处理失败';
          });
          await _cleanupResources();
          _showAnimatedToast('DLL文件处理失败，请重试', Colors.red, Icons.error);
          return;
        }
      }

      final dllPath = downloadResult.dllPath!;
      _addLogMessage('SUCCESS', 'DLL下载成功');
      await AppLogger.success('DLL文件下载成功: $dllPath');

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
          _addLogMessage('WARNING', '用户取消操作');
          setState(() {
            _statusMessage = '用户取消操作';
          });
          // 用户取消，停止日志监控并清理资源
          await _cleanupResources();
          return;
        }
        
        setState(() {
          _isLoading = true;
          _statusMessage = '正在关闭现有微信进程...';
        });
        _addLogMessage('INFO', '正在关闭现有微信进程...');
        
        DllInjector.killWeChatProcesses();
        await Future.delayed(const Duration(seconds: 2));
        _addLogMessage('SUCCESS', '已关闭现有微信进程');
      }

      // 3. 启动微信
      _addLogMessage('INFO', '正在启动微信...');
      setState(() {
        _statusMessage = '正在启动微信...';
      });

      final launched = await DllInjector.launchWeChat();
      if (!launched) {
        _addLogMessage('ERROR', '微信启动失败，请检查微信安装路径');
        await AppLogger.error('微信启动失败，可能原因：路径错误或微信未安装');
        setState(() {
          _isLoading = false;
          _statusMessage = '微信启动失败';
        });
        // 停止日志监控并清理资源
        await _cleanupResources();
        // 提示用户检查设置
        _showAnimatedToast('微信启动失败，请在设置中检查微信路径', Colors.red, Icons.error);
        
        // 延迟后自动打开设置对话框
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            _openSettings();
          }
        });
        return;
      }

      _addLogMessage('SUCCESS', '微信启动成功');

      // 4. 等待微信窗口出现
      _addLogMessage('INFO', '等待微信窗口出现...');
      setState(() {
        _statusMessage = '等待微信窗口出现...';
      });

      final windowAppeared = await DllInjector.waitForWeChatWindow(maxWaitSeconds: 15);
      if (!windowAppeared) {
        _addLogMessage('ERROR', '等待微信窗口超时，微信可能启动失败');
        await AppLogger.error('等待微信窗口超时');
        setState(() {
          _isLoading = false;
          _statusMessage = '等待微信窗口超时';
        });
        // 停止日志监控并清理资源
        await _cleanupResources();
        _showAnimatedToast('微信窗口未出现，请手动启动微信后重试', Colors.orange, Icons.warning);
        return;
      }

      // 5. 延迟几秒，等待微信完全初始化
      _addLogMessage('INFO', '等待微信完全启动，请不要点击微信任何按键');
      setState(() {
        _statusMessage = '等待微信完全启动...请不要点击微信任何按键';
      });
      for (int i = 5; i > 0; i--) {
        setState(() {
          _statusMessage = '等待微信完全启动... ($i秒)，请不要点击微信任何按键';
        });
        await Future.delayed(const Duration(seconds: 1));
      }

      // 6. 注入DLL
      _addLogMessage('INFO', '正在注入DLL...');
      setState(() {
        _statusMessage = '正在注入DLL...';
      });

      final success = DllInjector.injectDll('Weixin.exe', dllPath);
      
      if (success) {
        _addLogMessage('SUCCESS', 'DLL注入成功！等待密钥获取...');
        await AppLogger.success('DLL注入成功，开始等待密钥获取');
        setState(() {
          _isDllInjected = true;
          _statusMessage = 'DLL注入成功！等待密钥获取...';
        });
        
        // 设置超时，如果一段时间内没有收到密钥，则停止监听
        _startKeyTimeout();
      } else {
        _addLogMessage('ERROR', 'DLL注入失败，请确保以管理员身份运行');
        await AppLogger.error('DLL注入失败，可能未以管理员身份运行');
        setState(() {
          _statusMessage = 'DLL注入失败';
        });
        // 停止日志监控并清理资源
        await _cleanupResources();
      }
    } catch (e, stackTrace) {
      _addLogMessage('ERROR', '自动注入过程出错: $e');
      await AppLogger.error('自动注入过程出错', e, stackTrace);
      setState(() {
        _statusMessage = '自动注入失败: $e';
      });
      // 出错时停止日志监控并清理资源
      await _cleanupResources();
    } finally {
      setState(() {
        _isLoading = false;
      });
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

  /// 获取图片密钥（XOR和AES）
  Future<void> _getImageKeys() async {
    if (!_isWechatRunning) {
      _showAnimatedToast('请先启动微信', Colors.orange, Icons.warning);
      return;
    }

    setState(() {
      _isGettingImageKey = true;
    });

    try {
      _addLogMessage('INFO', '开始获取图片密钥...');
      await AppLogger.info('开始获取图片密钥');

      // 首次尝试自动获取
      var result = await ImageKeyService.getImageKeys();

      // 如果需要手动选择目录
      if (!result.success && result.needManualSelection) {
        _addLogMessage('WARNING', '未找到微信缓存目录，请手动选择');
        await AppLogger.warning('未找到微信缓存目录，请求用户手动选择');
        
        // 显示确认对话框
        final shouldSelectManually = await _showConfirmDialog(
          title: '未找到缓存目录',
          content: '无法自动找到微信缓存目录。\n\n通常位于：\nDocuments\\xwechat_files\\你的账号ID\n\n是否手动选择目录？',
          confirmText: '手动选择',
          cancelText: '取消',
        );
        
        if (!shouldSelectManually) {
          _addLogMessage('WARNING', '用户取消手动选择');
          await AppLogger.info('用户取消手动选择微信缓存目录');
          setState(() {
            _isGettingImageKey = false;
          });
          return;
        }
        
        // 让用户选择目录
        final selectedDirectory = await ImageKeyService.selectWeChatCacheDirectory();
        
        if (selectedDirectory == null || selectedDirectory.isEmpty) {
          _addLogMessage('WARNING', '未选择目录');
          await AppLogger.info('用户未选择微信缓存目录');
          _showAnimatedToast('未选择目录', Colors.orange, Icons.warning);
          setState(() {
            _isGettingImageKey = false;
          });
          return;
        }
        
        _addLogMessage('INFO', '已选择目录，重新尝试获取密钥...');
        await AppLogger.info('用户选择了目录: $selectedDirectory');
        
        // 使用选择的目录重新获取
        result = await ImageKeyService.getImageKeys(manualDirectory: selectedDirectory);
      }

      if (result.success && result.xorKey != null && result.aesKey != null) {
        final saveSuccess = await KeyStorage.saveImageKeys(result.xorKey!, result.aesKey!);
        
        if (saveSuccess) {
          setState(() {
            _imageXorKey = result.xorKey;
            _imageAesKey = result.aesKey;
            _imageKeyTimestamp = DateTime.now();
          });
          
          _addLogMessage('SUCCESS', '图片密钥获取成功');
          await AppLogger.success('图片密钥获取成功: XOR=0x${result.xorKey!.toRadixString(16).toUpperCase()}, AES=${result.aesKey}');
          _showAnimatedToast('图片密钥获取成功', Colors.green, Icons.check_circle);
        } else {
          _addLogMessage('ERROR', '图片密钥保存失败');
          await AppLogger.error('图片密钥保存失败');
          _showAnimatedToast('图片密钥保存失败', Colors.red, Icons.error);
        }
      } else {
        _addLogMessage('ERROR', result.error ?? '图片密钥获取失败');
        await AppLogger.error('图片密钥获取失败: ${result.error}');
        _showAnimatedToast(result.error ?? '图片密钥获取失败', Colors.red, Icons.error);
      }
    } catch (e, stackTrace) {
      _addLogMessage('ERROR', '获取图片密钥时出错');
      await AppLogger.error('获取图片密钥时出错', e, stackTrace);
      _showAnimatedToast('获取图片密钥时出错: $e', Colors.red, Icons.error);
    } finally {
      setState(() {
        _isGettingImageKey = false;
      });
    }
  }




  // 定期检查微信状态
  void _startStatusPolling() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _isPolling) {
        _checkWechatStatus();
        _startStatusPolling();
      }
    });
  }

  bool _isStoppingListener = false;
  
  Future<void> _checkWechatStatus() async {
    final isRunning = DllInjector.isProcessRunning('Weixin.exe');
    if (mounted) {
      setState(() {
        _isWechatRunning = isRunning;
        
        // 微信不运行时，重置注入状态并延迟停止监控
        if (!isRunning && _isDllInjected && !_isStoppingListener) {
          _isDllInjected = false;
          _isStoppingListener = true;
          
          // 微信崩溃时DLL会写入密钥到日志，延迟3秒停止监控以确保读取到密钥
          Future.delayed(const Duration(seconds: 3), () async {
            if (mounted) {
              await _cleanupResources();
              _isStoppingListener = false;
              
              // 如果还没有获取到密钥，提示用户
              if (_extractedKey == null && mounted) {
                setState(() {
                  if (_statusMessage.contains('监听')) {
                    _statusMessage = '微信已退出，未获取到密钥';
                  }
                });
                _addLogMessage('WARNING', '微信已退出，未获取到密钥');
              }
            }
          });
        }
        
        // 如果已经获取到密钥，不要覆盖状态消息
        if (!_isLoading && _extractedKey == null) {
          if (isRunning) {
            if (!_isDllInjected) {
              _statusMessage = _wechatVersion != null 
                  ? '检测到微信进程 (版本: $_wechatVersion)'
                  : '检测到微信进程';
            } else {
              _statusMessage = '正在监听密钥，请前往微信登录即可获取密钥';
            }
          } else {
            _statusMessage = _wechatVersion != null 
                ? '未检测到微信进程 (检测到版本: $_wechatVersion)'
                : '未检测到微信进程';
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
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'HarmonyOS_SansSC',
                  ),
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

  /// 显示网络错误弹窗
  Future<void> _showNetworkErrorDialog() async {
    await showDialog(
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
                  Icons.cloud_off_rounded,
                  color: Colors.orange,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '网络连接失败',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'HarmonyOS_SansSC',
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '无法从 GitHub 下载微信版本 $_wechatVersion 的 DLL 文件。',
                style: const TextStyle(
                  fontSize: 14,
                  fontFamily: 'HarmonyOS_SansSC',
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '可能原因：\n• 网络连接不稳定\n• 无法访问 GitHub\n• 代理或防火墙设置',
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: 'HarmonyOS_SansSC',
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '你可以自行前往github下载对应版本的 DLL 文件继续。',
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: 'HarmonyOS_SansSC',
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                '取消',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'HarmonyOS_SansSC',
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                _openDllDownloadPage();
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blue,
                side: const BorderSide(color: Colors.blue),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.download, size: 18),
              label: const Text(
                '前往下载',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontFamily: 'HarmonyOS_SansSC',
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                // 重试下载
                await _autoInjectDll();
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF07c160),
                side: const BorderSide(color: Color(0xFF07c160)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text(
                '重试',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontFamily: 'HarmonyOS_SansSC',
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _continueWithManualDll();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF07c160),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text(
                '选择本地 DLL',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontFamily: 'HarmonyOS_SansSC',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 显示版本未适配弹窗
  /// versionComparison: 1表示当前版本更新, -1表示当前版本更旧, null表示无法比较
  Future<void> _showVersionNotSupportedDialog(int? versionComparison) async {
    // 根据版本比较结果确定提示内容
    String tipMessage;
    IconData tipIcon;
    Color tipColor;
    Color tipIconColor;
    Color tipTextColor;
    
    if (versionComparison == 1) {
      // 当前版本比最新适配版本更新
      tipMessage = '当前版本较新以至于作者还没有更新\n请等待作者更新或提交 Issue 提醒作者';
      tipIcon = Icons.info_outline;
      tipColor = Colors.blue;
      tipIconColor = Colors.blue.shade700;
      tipTextColor = Colors.blue.shade900;
    } else if (versionComparison == -1) {
      // 当前版本比最新适配版本更旧
      tipMessage = '当前的旧版本不再会适配\n建议更新微信到最新版本';
      tipIcon = Icons.lightbulb_outline;
      tipColor = Colors.orange;
      tipIconColor = Colors.orange.shade700;
      tipTextColor = Colors.orange.shade900;
    } else {
      // 无法比较（网络问题等）
      tipMessage = '建议更新微信到最新版本\n或前往 GitHub 提交 Issue';
      tipIcon = Icons.lightbulb_outline;
      tipColor = Colors.orange;
      tipIconColor = Colors.orange.shade700;
      tipTextColor = Colors.orange.shade900;
    }
    
    await showDialog(
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
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '版本未适配',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'HarmonyOS_SansSC',
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '当前微信版本 $_wechatVersion 暂未适配。',
                style: const TextStyle(
                  fontSize: 14,
                  fontFamily: 'HarmonyOS_SansSC',
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tipColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: tipColor.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      tipIcon,
                      color: tipIconColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tipMessage,
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'HarmonyOS_SansSC',
                          height: 1.4,
                          color: tipTextColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                '关闭',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'HarmonyOS_SansSC',
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _openGitHubIssue();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF07c160),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              icon: const Icon(Icons.launch, size: 18),
              label: const Text(
                '前往 Issue',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontFamily: 'HarmonyOS_SansSC',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 打开GitHub Issue页面
  Future<void> _openGitHubIssue() async {
    try {
      final issueUrl = Uri.parse(
        'https://github.com/ycccccccy/wx_key/issues/new?title=请求适配微信版本 $_wechatVersion&body=当前微信版本：$_wechatVersion%0A%0A请求适配此版本的密钥提取功能。'
      );
      
      // 使用 url_launcher 打开浏览器
      if (await canLaunchUrl(issueUrl)) {
        await launchUrl(issueUrl, mode: LaunchMode.externalApplication);
        _showAnimatedToast('已在浏览器中打开 GitHub Issue', Colors.green, Icons.open_in_new);
      } else {
        _showAnimatedToast('无法打开浏览器', Colors.red, Icons.error);
      }
    } catch (e) {
      _showAnimatedToast('打开浏览器失败', Colors.red, Icons.error);
    }
  }

  /// 打开DLL下载页面
  Future<void> _openDllDownloadPage() async {
    try {
      final downloadUrl = Uri.parse('https://github.com/ycccccccy/wx_key/releases/tag/dlls');
      
      if (await canLaunchUrl(downloadUrl)) {
        await launchUrl(downloadUrl, mode: LaunchMode.externalApplication);
        _showAnimatedToast('已在浏览器中打开 DLL 下载页面', Colors.green, Icons.open_in_new);
      } else {
        _showAnimatedToast('无法打开浏览器', Colors.red, Icons.error);
      }
    } catch (e) {
      _showAnimatedToast('打开浏览器失败', Colors.red, Icons.error);
    }
  }

  /// 手动选择DLL文件
  Future<String?> _pickDllFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['dll'],
        dialogTitle: '选择DLL文件',
      );
      
      if (result != null && result.files.single.path != null) {
        return result.files.single.path!;
      }
      return null;
    } catch (e) {
      await AppLogger.error('选择DLL文件失败', e);
      _showAnimatedToast('选择文件失败', Colors.red, Icons.error);
      return null;
    }
  }

  /// 使用手动选择的DLL继续注入流程
  Future<void> _continueWithManualDll() async {
    final dllPath = await _pickDllFile();
    if (dllPath == null) {
      await AppLogger.info('用户取消选择DLL文件');
      return;
    }
    
    await AppLogger.info('用户手动选择了DLL文件: $dllPath');
    _showAnimatedToast('已选择DLL文件', Colors.green, Icons.check_circle);
    
    // 启动日志监控
    await _startLogMonitoring();
    
    setState(() {
      _isLoading = true;
      _statusMessage = '准备使用手动选择的DLL...';
    });
    
    try {
      // 检查微信是否运行，如果运行则请求用户确认关闭
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
          _addLogMessage('WARNING', '用户取消操作');
          setState(() {
            _statusMessage = '用户取消操作';
          });
          await _cleanupResources();
          return;
        }
        
        setState(() {
          _isLoading = true;
          _statusMessage = '正在关闭现有微信进程...';
        });
        _addLogMessage('INFO', '正在关闭现有微信进程...');
        
        DllInjector.killWeChatProcesses();
        await Future.delayed(const Duration(seconds: 2));
        _addLogMessage('SUCCESS', '已关闭现有微信进程');
      }

      // 启动微信
      _addLogMessage('INFO', '正在启动微信...');
      setState(() {
        _statusMessage = '正在启动微信...';
      });

      final launched = await DllInjector.launchWeChat();
      if (!launched) {
        _addLogMessage('ERROR', '微信启动失败，请检查微信安装路径');
        await AppLogger.error('微信启动失败');
        setState(() {
          _isLoading = false;
          _statusMessage = '微信启动失败';
        });
        await _cleanupResources();
        _showAnimatedToast('微信启动失败，请在设置中检查微信路径', Colors.red, Icons.error);
        return;
      }

      _addLogMessage('SUCCESS', '微信启动成功');

      // 等待微信窗口出现
      _addLogMessage('INFO', '等待微信窗口出现...');
      setState(() {
        _statusMessage = '等待微信窗口出现...';
      });

      final windowAppeared = await DllInjector.waitForWeChatWindow(maxWaitSeconds: 15);
      if (!windowAppeared) {
        _addLogMessage('ERROR', '等待微信窗口超时，微信可能启动失败');
        await AppLogger.error('等待微信窗口超时');
        setState(() {
          _isLoading = false;
          _statusMessage = '等待微信窗口超时';
        });
        await _cleanupResources();
        _showAnimatedToast('微信窗口未出现，请手动启动微信后重试', Colors.orange, Icons.warning);
        return;
      }

      // 延迟几秒，等待微信完全初始化
      _addLogMessage('INFO', '等待微信完全启动，请不要点击微信任何按键');
      setState(() {
        _statusMessage = '等待微信完全启动...请不要点击微信任何按键';
      });
      for (int i = 5; i > 0; i--) {
        setState(() {
          _statusMessage = '等待微信完全启动... ($i秒)，请不要点击微信任何按键';
        });
        await Future.delayed(const Duration(seconds: 1));
      }

      // 注入DLL
      _addLogMessage('INFO', '正在注入DLL...');
      setState(() {
        _statusMessage = '正在注入DLL...';
      });

      final success = DllInjector.injectDll('Weixin.exe', dllPath);
      
      if (success) {
        _addLogMessage('SUCCESS', 'DLL注入成功！等待密钥获取...');
        await AppLogger.success('DLL注入成功（手动选择），开始等待密钥获取');
        setState(() {
          _isDllInjected = true;
          _statusMessage = 'DLL注入成功！等待密钥获取...';
        });
        
        _startKeyTimeout();
      } else {
        _addLogMessage('ERROR', 'DLL注入失败，请确保以管理员身份运行');
        await AppLogger.error('DLL注入失败（手动选择）');
        setState(() {
          _statusMessage = 'DLL注入失败';
        });
        await _cleanupResources();
      }
    } catch (e, stackTrace) {
      _addLogMessage('ERROR', '注入过程出错: $e');
      await AppLogger.error('手动DLL注入过程出错', e, stackTrace);
      setState(() {
        _statusMessage = '注入失败: $e';
      });
      await _cleanupResources();
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }


  /// 打开设置对话框
  Future<void> _openSettings() async {
    await AppLogger.info('用户打开设置页面');
    showDialog(
      context: context,
      builder: (context) => SettingsDialog(
        onWechatDirectoryChanged: () async {
          // 重新检测版本
          await _detectWeChatVersion();
        },
      ),
    );
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

  Widget _buildImageKeyButton() {
    return Container(
      width: double.infinity,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: _getImageKeys,
        label: const Text(
          '获取图片密钥',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            fontFamily: 'HarmonyOS_SansSC',
            letterSpacing: 0.3,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue.shade600,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
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
                '数据库密钥',
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

  Widget _buildImageKeyCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.blue.withOpacity(0.15),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.05),
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
                '图片密钥',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                  fontFamily: 'HarmonyOS_SansSC',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'XOR 密钥:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                        fontFamily: 'HarmonyOS_SansSC',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SelectableText(
                        '0x${_imageXorKey!.toRadixString(16).toUpperCase().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontFamily: 'HarmonyOS_SansSC',
                          color: Colors.black87,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _copyKeyToClipboard('0x${_imageXorKey!.toRadixString(16).toUpperCase().padLeft(2, '0')}'),
                      icon: const Icon(Icons.content_copy_rounded, size: 14, color: Colors.blue),
                      label: const Text(
                        '复制',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue,
                          fontFamily: 'HarmonyOS_SansSC',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        backgroundColor: Colors.blue.withOpacity(0.08),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    Text(
                      'AES 密钥:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                        fontFamily: 'HarmonyOS_SansSC',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SelectableText(
                        _imageAesKey!,
                        style: const TextStyle(
                          fontSize: 13,
                          fontFamily: 'HarmonyOS_SansSC',
                          color: Colors.black87,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _copyKeyToClipboard(_imageAesKey!),
                      icon: const Icon(Icons.content_copy_rounded, size: 14, color: Colors.blue),
                      label: const Text(
                        '复制',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue,
                          fontFamily: 'HarmonyOS_SansSC',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        backgroundColor: Colors.blue.withOpacity(0.08),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_imageKeyTimestamp != null) ...[
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
                  '获取时间: ${_imageKeyTimestamp!.toString().substring(0, 19)}',
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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
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
                  // 设置按钮
                  IconButton(
                    onPressed: _openSettings,
                    tooltip: '设置',
                    icon: Icon(
                      Icons.settings_outlined,
                      color: Colors.grey.shade600,
                      size: 22,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey.shade100,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
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
                    if (!_isDllInjected && !_isLoading)
                      _buildSimpleActionButton(),
                    const SizedBox(height: 20),
                    
                    // 图片密钥获取按钮
                    if (_isWechatRunning && !_isGettingImageKey)
                      _buildImageKeyButton(),
                    const SizedBox(height: 32),
                    
                    // 数据库密钥显示
                    if (_savedKey != null) ...[
                      _buildSimpleKeyCard(),
                      const SizedBox(height: 20),
                    ],
                    
                    // 图片密钥显示
                    if (_imageXorKey != null && _imageAesKey != null) ...[
                      _buildImageKeyCard(),
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
