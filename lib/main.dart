import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:async';
import 'services/dll_injector.dart';
import 'services/key_storage.dart';
import 'services/pipe_listener.dart';

void main() {
  runApp(const MyApp());
}

/// 优雅的动画提示组件
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
          seedColor: const Color(0xFF07c160), // 微信绿
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
  bool _isDllExists = false;
  String _statusMessage = '未检测到微信进程';
  String _logFilePath = '';
  String _dllPath = '';
  
  // 新增状态变量
  String? _extractedKey;
  String? _savedKey;
  DateTime? _keyTimestamp;
  bool _isPipeListening = false;

  @override
  void initState() {
    super.initState();
    _initLogPath();
    _loadSavedData();
    _checkDllExists();
    _checkWechatStatus();
    _autoLaunchWeChatIfNeeded();
    _startStatusPolling();
    _startPipeListener();
  }

  @override
  void dispose() {
    PipeListener.stopListening();
    super.dispose();
  }

  Future<void> _initLogPath() async {
    try {
      // Use USERPROFILE environment variable to match DLL log path
      final userProfile = Platform.environment['USERPROFILE'] ?? 'C:\\Users\\cc';
      final logPath = path.join(userProfile, 'Documents', 'WechatKeyHunter_Log.txt');
      
      setState(() {
        _logFilePath = logPath;
      });
      
      print('Log file path initialized: $_logFilePath');
    } catch (e) {
      print('Error initializing log path: $e');
      setState(() {
        _logFilePath = 'C:\\Users\\cc\\Documents\\WechatKeyHunter_Log.txt';
      });
    }
  }

  /// 加载保存的数据
  Future<void> _loadSavedData() async {
    try {
      // 加载保存的DLL路径
      final savedDllPath = await KeyStorage.getDllPath();
      if (savedDllPath != null && savedDllPath.isNotEmpty) {
        setState(() {
          _dllPath = savedDllPath;
        });
      } else {
        // 如果没有保存的DLL路径，提示用户选择
        _showDllSelectionDialog();
      }

      // 加载保存的密钥信息
      final keyInfo = await KeyStorage.getKeyInfo();
      if (keyInfo != null) {
        setState(() {
          _savedKey = keyInfo['key'] as String;
          _keyTimestamp = keyInfo['timestamp'] as DateTime?;
        });
      }
    } catch (e) {
      print('加载保存数据失败: $e');
    }
  }

  /// 启动命名管道监听
  Future<void> _startPipeListener() async {
    try {
      final success = await PipeListener.startListening();
      setState(() {
        _isPipeListening = success;
      });

      if (success) {
        // 监听密钥流
        PipeListener.keyStream.listen((key) {
          print('[+] 收到密钥数据: ${key.length} 字符, 内容: ${key.length > 0 ? key.substring(0, key.length > 20 ? 20 : key.length) : "空"}');
          _onKeyReceived(key);
        });
        print('[+] 管道监听启动成功');
      } else {
        print('[-] 管道监听启动失败');
      }
      
      // 启动备份文件监控（以防管道通信失败）
      _startBackupFileMonitoring();
    } catch (e) {
      print('启动管道监听失败: $e');
    }
  }

  /// 监控备份文件
  void _startBackupFileMonitoring() {
    Timer.periodic(const Duration(seconds: 1), (timer) async {
      try {
        final backupFile = File(r'C:\temp\wechat_key_backup.txt');
        if (await backupFile.exists()) {
          final content = await backupFile.readAsString();
          if (content.trim().isNotEmpty && _extractedKey == null) {
            print('[Backup] 从备份文件读取到密钥');
            _onKeyReceived(content.trim());
            // 删除备份文件，避免重复读取
            await backupFile.delete();
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
      print('[+] _onKeyReceived 被调用，密钥长度: ${key.length}');
      print('[+] 密钥内容: ${key.length > 0 ? key.substring(0, key.length > 50 ? 50 : key.length) : "空"}');
      
      setState(() {
        _extractedKey = key;
      });

      // 自动保存密钥
      final success = await KeyStorage.saveKey(key);
      if (success) {
        setState(() {
          _savedKey = key;
          _keyTimestamp = DateTime.now();
        });
        _showAnimatedToast('密钥已自动保存', Colors.green, Icons.check_circle);
        print('[+] 密钥保存成功');
      } else {
        _showAnimatedToast('密钥保存失败', Colors.red, Icons.error);
        print('[-] 密钥保存失败');
      }
    } catch (e) {
      print('处理接收到的密钥失败: $e');
    }
  }

  /// 显示DLL选择对话框
  void _showDllSelectionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.folder_open, color: Color(0xFF07c160)),
              SizedBox(width: 8),
              Text('选择DLL文件'),
            ],
          ),
          content: const Text(
            '首次使用需要选择DLL文件。请选择您的wx_key.dll文件。',
            style: TextStyle(fontFamily: 'HarmonyOS_SansSC'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _selectDllFile();
              },
              child: const Text(
                '选择文件',
                style: TextStyle(
                  color: Color(0xFF07c160),
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

  /// 选择DLL文件
  Future<void> _selectDllFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['dll'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final selectedPath = result.files.single.path!;
        setState(() {
          _dllPath = selectedPath;
        });

        // 保存选择的路径
        await KeyStorage.saveDllPath(selectedPath);
        _checkDllExists();
        _showAnimatedToast('DLL文件已选择', Colors.green, Icons.check_circle);
      }
    } catch (e) {
      _showAnimatedToast('选择DLL文件失败: $e', Colors.red, Icons.error);
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

  /// 清除保存的密钥
  Future<void> _clearSavedKey() async {
    try {
      final success = await KeyStorage.clearKey();
      if (success) {
        setState(() {
          _savedKey = null;
          _keyTimestamp = null;
        });
        _showAnimatedToast('已清除保存的密钥', Colors.green, Icons.delete);
      } else {
        _showAnimatedToast('清除密钥失败', Colors.red, Icons.error);
      }
    } catch (e) {
      _showAnimatedToast('清除密钥失败: $e', Colors.red, Icons.error);
    }
  }


  Future<void> _checkDllExists() async {
    try {
      if (_dllPath.isEmpty) {
        setState(() {
          _isDllExists = false;
        });
        return;
      }
      
      final dllFile = File(_dllPath);
      final exists = await dllFile.exists();
      setState(() {
        _isDllExists = exists;
      });
      print('DLL file exists: $exists at $_dllPath');
    } catch (e) {
      print('Error checking DLL file: $e');
      setState(() {
        _isDllExists = false;
      });
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
        if (isRunning) {
          if (_dllPath.isEmpty) {
            _statusMessage = '请先选择DLL文件';
          } else if (!_isDllExists) {
            _statusMessage = 'DLL文件不存在，请检查路径';
          } else if (!_isDllInjected) {
            _statusMessage = '检测到微信进程，可以开始注入';
          } else {
            _statusMessage = 'DLL已注入，正在监听密钥';
          }
        } else {
          _statusMessage = '未检测到微信进程';
          _isDllInjected = false;
        }
      });
    }
  }

  Future<void> _autoLaunchWeChatIfNeeded() async {
    // Wait a moment for initial status check to complete
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (!_isWechatRunning) {
      print('[*] WeChat not running, attempting to launch...');
      setState(() {
        _statusMessage = '正在启动微信...';
      });
      
      final success = await DllInjector.launchWeChat();
      if (success) {
        setState(() {
          _statusMessage = '微信启动成功，可以开始注入';
        });
        _showAnimatedToast('微信已自动启动', Colors.green, Icons.check_circle);
      } else {
        setState(() {
          _statusMessage = '微信启动失败，请手动启动';
        });
        _showAnimatedToast('微信启动失败，请检查安装路径', Colors.orange, Icons.warning);
      }
    }
  }

  Future<void> _launchWeChat() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '正在启动微信...';
    });

    try {
      final success = await DllInjector.launchWeChat();
      if (success) {
        setState(() {
          _statusMessage = '微信启动成功，可以开始注入';
        });
        _showAnimatedToast('微信启动成功', Colors.green, Icons.check_circle);
      } else {
        setState(() {
          _statusMessage = '微信启动失败，请检查安装路径';
        });
        _showAnimatedToast('微信启动失败，请检查安装路径', Colors.red, Icons.error);
      }
    } catch (e) {
      setState(() {
        _statusMessage = '启动微信时出错';
      });
      _showAnimatedToast('启动微信时出错: $e', Colors.red, Icons.error);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _injectDll() async {
    if (!_isWechatRunning) {
      _showAnimatedToast('请先启动微信!', Colors.red, Icons.warning);
      return;
    }

    // 检查是否已选择DLL文件
    if (_dllPath.isEmpty) {
      _showAnimatedToast('请先选择DLL文件!', Colors.orange, Icons.warning);
      _showDllSelectionDialog();
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 检查DLL文件是否存在
      final dllFile = File(_dllPath);
      if (!await dllFile.exists()) {
        _showAnimatedToast('DLL文件不存在: $_dllPath', Colors.red, Icons.error);
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final success = DllInjector.injectDll('Weixin.exe', _dllPath);
      
      if (success) {
        setState(() {
          _isDllInjected = true;
          _statusMessage = 'DLL注入成功！正在监听密钥...';
        });
        _showAnimatedToast('DLL注入成功！', Colors.green, Icons.check_circle);
      } else {
        _showAnimatedToast('DLL注入失败！请确保以管理员身份运行', Colors.red, Icons.error);
      }
    } catch (e) {
      _showAnimatedToast('注入过程出错: $e', Colors.red, Icons.error);
    } finally {
      setState(() {
        _isLoading = false;
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

  Widget _buildStatusItem({
    required IconData icon,
    required Color color,
    required String title,
    required String status,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: color,
            size: 20,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey,
                  fontFamily: 'HarmonyOS_SansSC',
                ),
              ),
              const SizedBox(height: 2),
              Text(
                status,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: color,
                  fontFamily: 'HarmonyOS_SansSC',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required VoidCallback? onTap,
    required IconData icon,
    required String label,
    required bool isPrimary,
    bool isLoading = false,
  }) {
    final isEnabled = onTap != null;
    final backgroundColor = isEnabled 
        ? (isPrimary ? const Color(0xFF07c160) : Colors.grey.shade100)
        : Colors.grey.shade200;
    final textColor = isEnabled 
        ? (isPrimary ? Colors.white : Colors.black87)
        : Colors.grey;
    final iconColor = isEnabled 
        ? (isPrimary ? Colors.white : const Color(0xFF07c160))
        : Colors.grey;

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isEnabled ? [
          BoxShadow(
            color: isPrimary ? const Color(0xFF07c160).withOpacity(0.3) : Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ] : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else
                  Icon(icon, color: iconColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'HarmonyOS_SansSC',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKeyDisplay({
    required String title,
    required String key,
    DateTime? timestamp,
    bool showCopyButton = false,
    bool showClearButton = false,
    bool isCurrent = false,
  }) {
    final formattedTime = timestamp != null 
        ? '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}'
        : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCurrent ? const Color(0xFF07c160).withOpacity(0.05) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrent ? const Color(0xFF07c160).withOpacity(0.3) : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isCurrent ? Icons.flash_on : Icons.save,
                color: isCurrent ? const Color(0xFF07c160) : Colors.grey.shade600,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isCurrent ? const Color(0xFF07c160) : Colors.grey.shade700,
                  fontFamily: 'HarmonyOS_SansSC',
                ),
              ),
              const Spacer(),
              if (showCopyButton)
                GestureDetector(
                  onTap: () => _copyKeyToClipboard(key),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF07c160).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.copy,
                      color: Color(0xFF07c160),
                      size: 16,
                    ),
                  ),
                ),
              if (showClearButton) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _clearSavedKey,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.clear,
                      color: Colors.red,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            key,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'Courier New',
              color: Colors.black87,
              backgroundColor: Colors.white,
            ),
          ),
          if (formattedTime != null) ...[
            const SizedBox(height: 8),
            Text(
              '获取时间: $formattedTime',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontFamily: 'HarmonyOS_SansSC',
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: Column(
          children: [
            // 简约的标题栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF07c160),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF07c160).withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.chat,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'HarmonyOS_SansSC',
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'WeChat Key Extractor',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            fontFamily: 'HarmonyOS_SansSC',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 主内容区域
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 状态卡片 - 简约设计
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.grey.shade200,
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF07c160).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.info_outline,
                                    color: Color(0xFF07c160),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  '当前状态',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                    fontFamily: 'HarmonyOS_SansSC',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            
                            // 状态项
                            _buildStatusItem(
                              icon: _isWechatRunning ? Icons.check_circle : Icons.cancel,
                              color: _isWechatRunning ? const Color(0xFF07c160) : Colors.red,
                              title: '微信进程',
                              status: _isWechatRunning ? '运行中' : '未运行',
                            ),
                            
                            const SizedBox(height: 16),
                            
                            _buildStatusItem(
                              icon: _dllPath.isEmpty ? Icons.help_outline : (_isDllExists ? Icons.build : Icons.error),
                              color: _dllPath.isEmpty ? Colors.orange : (_isDllExists ? const Color(0xFF07c160) : Colors.red),
                              title: 'DLL文件',
                              status: _dllPath.isEmpty ? '未选择' : (_isDllExists ? '存在' : '不存在'),
                            ),
                            
                            const SizedBox(height: 16),
                            
                            _buildStatusItem(
                              icon: _isDllInjected ? Icons.check_circle : Icons.cancel,
                              color: _isDllInjected ? const Color(0xFF07c160) : Colors.grey,
                              title: 'DLL状态',
                              status: _isDllInjected ? '已注入' : '未注入',
                            ),
                            
                            const SizedBox(height: 16),
                            
                            _buildStatusItem(
                              icon: _isPipeListening ? Icons.router : Icons.router_outlined,
                              color: _isPipeListening ? const Color(0xFF07c160) : Colors.grey,
                              title: '管道监听',
                              status: _isPipeListening ? '监听中' : '未监听',
                            ),
                            
                            const SizedBox(height: 20),
                            
                            // 状态消息
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: _isWechatRunning ? const Color(0xFF07c160).withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _isWechatRunning ? const Color(0xFF07c160).withOpacity(0.3) : Colors.orange.withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _isWechatRunning ? Icons.verified : Icons.warning,
                                    color: _isWechatRunning ? const Color(0xFF07c160) : Colors.orange,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _statusMessage,
                                      style: TextStyle(
                                        color: _isWechatRunning ? const Color(0xFF07c160) : Colors.orange.shade700,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 14,
                                        fontFamily: 'HarmonyOS_SansSC',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // 密钥显示卡片
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.grey.shade200,
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF07c160).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.key,
                                    color: Color(0xFF07c160),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  '密钥信息',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                    fontFamily: 'HarmonyOS_SansSC',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            
                            // 当前提取的密钥
                            if (_extractedKey != null) ...[
                              _buildKeyDisplay(
                                title: '当前提取的密钥',
                                key: _extractedKey!,
                                showCopyButton: true,
                                isCurrent: true,
                              ),
                              const SizedBox(height: 16),
                            ],
                            
                            // 已保存的密钥
                            if (_savedKey != null) ...[
                              _buildKeyDisplay(
                                title: '已保存的密钥',
                                key: _savedKey!,
                                timestamp: _keyTimestamp,
                                showCopyButton: true,
                                showClearButton: true,
                              ),
                            ] else ...[
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey.shade200),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: Colors.grey.shade600,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        '暂无保存的密钥',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 14,
                                          fontFamily: 'HarmonyOS_SansSC',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // 操作按钮区域 - 简约设计
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.grey.shade200,
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF07c160).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.settings,
                                    color: Color(0xFF07c160),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  '操作控制',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                    fontFamily: 'HarmonyOS_SansSC',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            
                            // 主要操作按钮
                            Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: _buildActionButton(
                                    onTap: _isLoading || !_isWechatRunning || _isDllInjected || _dllPath.isEmpty || !_isDllExists ? null : _injectDll,
                                    icon: _isLoading ? Icons.hourglass_empty : Icons.play_arrow,
                                    label: _isLoading ? '注入中...' : '开始注入',
                                    isPrimary: true,
                                    isLoading: _isLoading,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                _buildActionButton(
                                  onTap: _launchWeChat,
                                  icon: Icons.launch,
                                  label: '启动微信',
                                  isPrimary: false,
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // DLL选择按钮
                            _buildActionButton(
                              onTap: _selectDllFile,
                              icon: Icons.folder_open,
                              label: '选择DLL文件',
                              isPrimary: false,
                            ),
                            
                            const SizedBox(height: 16),
                            
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
