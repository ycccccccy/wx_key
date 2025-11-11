import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:path/path.dart' as path;
import 'services/dll_injector.dart';
import 'services/remote_hook_controller.dart'; // 新增：远程Hook控制器
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

class _StatusVisual {
  const _StatusVisual({
    required this.stateKey,
    required this.background,
    required this.border,
    required this.iconColor,
    required this.icon,
    required this.shadow,
  });

  final String stateKey;
  final Color background;
  final Color border;
  final Color iconColor;
  final IconData icon;
  final Color shadow;
}

enum _BadgeGlyphType { exclamation, check }

class _CircularArrowGlyphPainter extends CustomPainter {
  const _CircularArrowGlyphPainter({
    required this.progress,
    required this.color,
    required this.emphasize,
  });

  final double progress;
  final Color color;
  final bool emphasize;

  @override
  void paint(Canvas canvas, Size size) {
    final double diameter = size.shortestSide;
    final double radius = diameter / 2;
    final Offset center = Offset(size.width / 2, size.height / 2);

    final double innerRadius = radius - 4;
    final double arrowHeight = diameter * (emphasize ? 0.6 : 0.54);
    final double arrowWidth = diameter * (emphasize ? 0.46 : 0.4);
    final double travel = innerRadius * 2 + arrowHeight * 1.6;
    final double baseLine =
        center.dy + innerRadius + arrowHeight + 6; // fully below the circle

    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: innerRadius)),
    );

    for (int i = 0; i < 2; i++) {
      final double phase = (progress + i * 0.5) % 1.0;
      final double eased = Curves.easeInOut.transform(phase);
      final double topY = baseLine - eased * travel - arrowHeight;
      final double opacity = (1 - eased).clamp(0.0, 1.0);
      _drawArrow(
        canvas,
        center.dx,
        topY,
        arrowWidth,
        arrowHeight,
        color,
        opacity,
      );
    }

    canvas.restore();
  }

  void _drawArrow(
    Canvas canvas,
    double centerX,
    double topY,
    double width,
    double height,
    Color color,
    double opacity,
  ) {
    final double headHeight = height * 0.36;
    final double bodyWidth = width * 0.42;
    final double baseY = topY + height;

    final Path arrow = Path()
      ..moveTo(centerX, topY)
      ..lineTo(centerX - width / 2, topY + headHeight)
      ..lineTo(centerX - bodyWidth / 2, topY + headHeight)
      ..lineTo(centerX - bodyWidth / 2, baseY)
      ..lineTo(centerX + bodyWidth / 2, baseY)
      ..lineTo(centerX + bodyWidth / 2, topY + headHeight)
      ..lineTo(centerX + width / 2, topY + headHeight)
      ..close();

    final Rect gradientRect = Rect.fromLTWH(
      centerX - width / 2,
      topY,
      width,
      height,
    );

    final Paint arrowPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          color.withOpacity(0.9 * opacity),
          color.withOpacity(0.5 * opacity),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(gradientRect);

    canvas.drawShadow(arrow, color.withOpacity(0.25 * opacity), 6, false);
    canvas.drawPath(arrow, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _CircularArrowGlyphPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.emphasize != emphasize;
  }
}

class _CircularBadgeBackgroundPainter extends CustomPainter {
  const _CircularBadgeBackgroundPainter({
    required this.color,
    required this.emphasize,
  });

  final Color color;
  final bool emphasize;

  @override
  void paint(Canvas canvas, Size size) {
    final double diameter = size.shortestSide;
    final double radius = diameter / 2;
    final Offset center = Offset(size.width / 2, size.height / 2);

    final Paint fillPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withOpacity(emphasize ? 0.32 : 0.24),
          color.withOpacity(emphasize ? 0.12 : 0.08),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, fillPaint);

    final Paint borderPaint = Paint()
      ..color = color.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = emphasize ? 2.2 : 1.8;
    canvas.drawCircle(
      center,
      radius - borderPaint.strokeWidth / 2,
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CircularBadgeBackgroundPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.emphasize != emphasize;
  }
}

class _StatusGlyphPainter extends CustomPainter {
  const _StatusGlyphPainter({
    required this.type,
    required this.color,
    required this.emphasize,
    required this.progress,
  });

  final _BadgeGlyphType type;
  final Color color;
  final bool emphasize;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final double insetFactor = emphasize ? 0.18 : 0.22;
    final double inset = size.shortestSide * insetFactor;
    final Rect drawBounds = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );
    final Shader shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        color.withOpacity(0.96),
        color.withOpacity(0.6),
      ],
    ).createShader(drawBounds);

    switch (type) {
      case _BadgeGlyphType.check:
        _paintCheckGlyph(canvas, drawBounds, shader);
        break;
      case _BadgeGlyphType.exclamation:
        _paintExclamationGlyph(canvas, drawBounds, shader);
        break;
    }
  }

  void _paintCheckGlyph(Canvas canvas, Rect bounds, Shader shader) {
    final double strokeWidth = bounds.shortestSide * 0.18;
    final Path checkPath = Path()
      ..moveTo(
        bounds.left + bounds.width * 0.14,
        bounds.top + bounds.height * 0.55,
      )
      ..lineTo(
        bounds.left + bounds.width * 0.39,
        bounds.top + bounds.height * 0.82,
      )
      ..lineTo(
        bounds.left + bounds.width * 0.86,
        bounds.top + bounds.height * 0.2,
      );

    final double reveal =
        Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    final Rect clipRect = Rect.fromLTWH(
      bounds.left,
      bounds.top,
      bounds.width,
      bounds.height * reveal,
    );

    canvas.save();
    canvas.clipRect(clipRect);

    final Paint glowPaint = Paint()
      ..color = color.withOpacity(0.28 * reveal)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.2);
    canvas.drawPath(checkPath, glowPaint);

    final Paint strokePaint = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(checkPath, strokePaint);
    canvas.restore();
  }

  void _paintExclamationGlyph(Canvas canvas, Rect bounds, Shader shader) {
    final double t = progress.clamp(0.0, 1.0);
    final double wobble =
        math.sin(t * math.pi * 3) * (1 - t) * (emphasize ? 0.28 : 0.24);
    final double opacity = Curves.easeOut.transform(t);
    final double barWidth = bounds.width * 0.18;
    final double barHeight = bounds.height * 0.58;
    final RRect bar = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(bounds.center.dx, bounds.top + barHeight / 2),
        width: barWidth,
        height: barHeight,
      ),
      Radius.circular(barWidth / 2),
    );

    final double dotRadius = barWidth * 0.7;
    final Offset dotCenter = Offset(
      bounds.center.dx,
      bounds.bottom - dotRadius * 0.9,
    );

    canvas.save();
    canvas.translate(bounds.center.dx, bounds.center.dy);
    canvas.rotate(wobble);
    canvas.translate(-bounds.center.dx, -bounds.center.dy);

    final Paint glowPaint = Paint()
      ..color = color.withOpacity(0.22 * opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawRRect(bar, glowPaint);
    canvas.drawCircle(dotCenter, dotRadius, glowPaint);

    final Paint fillPaint = Paint()
      ..shader = shader
      ..style = PaintingStyle.fill;
    canvas.drawRRect(bar, fillPaint);
    canvas.drawCircle(dotCenter, dotRadius, fillPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StatusGlyphPainter oldDelegate) {
    return oldDelegate.type != type ||
        oldDelegate.color != color ||
        oldDelegate.emphasize != emphasize ||
        oldDelegate.progress != progress;
  }
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
          displayLarge: TextStyle(
            fontFamily: 'HarmonyOS_SansSC',
            fontWeight: FontWeight.w700,
          ),
          displayMedium: TextStyle(
            fontFamily: 'HarmonyOS_SansSC',
            fontWeight: FontWeight.w600,
          ),
          displaySmall: TextStyle(
            fontFamily: 'HarmonyOS_SansSC',
            fontWeight: FontWeight.w500,
          ),
          headlineLarge: TextStyle(
            fontFamily: 'HarmonyOS_SansSC',
            fontWeight: FontWeight.w600,
          ),
          headlineMedium: TextStyle(
            fontFamily: 'HarmonyOS_SansSC',
            fontWeight: FontWeight.w500,
          ),
          headlineSmall: TextStyle(
            fontFamily: 'HarmonyOS_SansSC',
            fontWeight: FontWeight.w500,
          ),
          titleLarge: TextStyle(
            fontFamily: 'HarmonyOS_SansSC',
            fontWeight: FontWeight.w600,
          ),
          titleMedium: TextStyle(
            fontFamily: 'HarmonyOS_SansSC',
            fontWeight: FontWeight.w500,
          ),
          titleSmall: TextStyle(
            fontFamily: 'HarmonyOS_SansSC',
            fontWeight: FontWeight.w500,
          ),
          bodyLarge: TextStyle(
            fontFamily: 'HarmonyOS_SansSC',
            fontWeight: FontWeight.w400,
          ),
          bodyMedium: TextStyle(
            fontFamily: 'HarmonyOS_SansSC',
            fontWeight: FontWeight.w400,
          ),
          bodySmall: TextStyle(
            fontFamily: 'HarmonyOS_SansSC',
            fontWeight: FontWeight.w400,
          ),
          labelLarge: TextStyle(
            fontFamily: 'HarmonyOS_SansSC',
            fontWeight: FontWeight.w500,
          ),
          labelMedium: TextStyle(
            fontFamily: 'HarmonyOS_SansSC',
            fontWeight: FontWeight.w500,
          ),
          labelSmall: TextStyle(
            fontFamily: 'HarmonyOS_SansSC',
            fontWeight: FontWeight.w500,
          ),
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

class _MyHomePageState extends State<MyHomePage>
    with WindowListener, SingleTickerProviderStateMixin {
  bool _isWechatRunning = false;
  bool _isDllInjected = false;
  bool _isLoading = false;
  String _statusMessage = '未检测到微信进程';
  String _statusLevel = 'INFO';

  // 新增状态变量
  String? _extractedKey;
  String? _currentSessionKey;
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

  late final AnimationController _statusBackdropController;

  // 超时定时器
  Timer? _keyTimeoutTimer;

  // 日志流订阅
  StreamSubscription<Map<String, dynamic>>? _logStreamSubscription;

  @override
  void initState() {
    super.initState();
    _statusBackdropController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
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
    _statusBackdropController.dispose();
    // 清理远程Hook控制器
    RemoteHookController.dispose();
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

  /// æ¸çææèµæº
  Future<void> _cleanupResources() async {
    print('[æ¸ç] å¼å§æ¸çèµæº...');

    // åæ­¢ç¶æè½®è¯¢
    _isPolling = false;
    print('[æ¸ç] ç¶æè½®è¯¢å·²åæ­¢');

    // å¸è½½è¿ç¨ Hook
    if (_isDllInjected) {
      print('[æ¸ç] å¼å§å¸è½½è¿ç¨Hook...');
      RemoteHookController.uninstallHook();
      print('[æ¸ç] è¿ç¨Hookå·²å¸è½½');
    }

    // åæ¶æ¥å¿æµè®¢é
    await _logStreamSubscription?.cancel();
    _logStreamSubscription = null;
    print('[æ¸ç] æ¥å¿æµè®¢éå·²åæ¶');

    // ç¨ç­çå»ï¼ç¡®ä¿åå°çº¿ç¨ç»æ
    await Future.delayed(const Duration(milliseconds: 300));
    print('[æ¸ç] èµæºæ¸çå®æ');

    if (mounted) {
      setState(() {
        _isDllInjected = false;
        _isLoading = false;
        _isGettingImageKey = false;
      });
    }
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
          _statusLevel = 'INFO';
        });
        await AppLogger.success('检测到微信版本: $version');
      } else {
        setState(() {
          _statusMessage = '未找到微信安装目录';
          _statusLevel = 'WARNING';
        });
        _addLogMessage('WARNING', '未找到微信安装目录');
        await AppLogger.warning('未找到微信安装目录');
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

  bool _isDuplicateLog(String type, String message) {
    return _logMessages.any(
      (log) => log['type'] == type && log['message'] == message,
    );
  }

  /// 添加日志消息
  void _addLogMessage(String type, String message) {
    if (_isDuplicateLog(type, message)) {
      return;
    }

    setState(() {
      _logMessages.insert(0, {'type': type, 'message': message});
      if (_logMessages.length > _maxLogMessages) {
        _logMessages.removeLast();
      }

      final bool isInfoOrSuccess = type == 'INFO' || type == 'SUCCESS';
      final bool isWarningOrError = type == 'WARNING' || type == 'ERROR';
      final bool shouldUpdateInfoState =
          isInfoOrSuccess && _extractedKey == null;
      if (shouldUpdateInfoState || isWarningOrError) {
        _statusMessage = message;
        _statusLevel = type;
      }
    });
  }

  /// 处理接收到的密钥
  Future<void> _onKeyReceived(String key) async {
    try {
      if (_currentSessionKey == key) {
        return; // 忽略会重复刷新的相同密钥
      }
      _currentSessionKey = key;

      await AppLogger.success('成功接收到密钥: ${key.substring(0, 8)}...');
      _keyTimeoutTimer?.cancel();
      _addLogMessage('KEY', key);
      setState(() {
        _extractedKey = key;
        _savedKey = key;
        _keyTimestamp = DateTime.now();
        _statusMessage = '密钥获取成功！';
        _statusLevel = 'SUCCESS';
      });
      _addLogMessage('SUCCESS', '密钥获取成功！');

      // 自动保存密钥（即便持久化失败也保持UI实时）
      final saveSuccess = await KeyStorage.saveKey(key);
      if (saveSuccess) {
        await AppLogger.success('密钥已自动保存');
        _addLogMessage('SUCCESS', '密钥已自动保存');
      } else {
        await AppLogger.error('密钥保存失败');
        _addLogMessage('ERROR', '密钥保存失败');
      }

      // 自动复制到剪贴板（只执行一次）
      await _copyKeyToClipboard(key);

      // 密钥获取成功后，延迟停止日志监控以释放资源
      Future.delayed(const Duration(seconds: 3), () async {
        if (mounted) {
          await _cleanupResources();
        }
      });
    } catch (e, stackTrace) {
      await AppLogger.error('处理接收到的密钥时出错', e, stackTrace);
    }
  }

  /// 启动密钥获取超时计时器
  void _startKeyTimeout() {
    // 取消之前的定时器
    _keyTimeoutTimer?.cancel();

    // 60秒后如果还没有获取到密钥，停止监听
    _keyTimeoutTimer = Timer(const Duration(seconds: 60), () async {
      if (mounted && _extractedKey == null && _isDllInjected) {
        await _cleanupResources();
        setState(() {
          _statusMessage = '密钥获取超时，请重新尝试';
          _statusLevel = 'WARNING';
          _isDllInjected = false;
        });
        _addLogMessage('WARNING', '密钥获取超时，请重新尝试');
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
      _currentSessionKey = null;
      _isStoppingListener = false;
    });

    // 启动日志监控
    await _startLogMonitoring();

    setState(() {
      _isLoading = true;
      _statusMessage = '准备开始获取密钥...';
      _statusLevel = 'INFO';
    });
    _addLogMessage('INFO', '准备开始获取密钥...');
    await AppLogger.info('用户开始获取密钥流程，微信版本: $_wechatVersion');

    try {
      // 1. 准备内置DLL
      _addLogMessage('INFO', '正在准备内置DLL文件');
      setState(() {
        _statusMessage = '正在准备内置DLL文件';
        _statusLevel = 'INFO';
      });
      await AppLogger.info('开始准备内置DLL文件');

      // 提取DLL到临时目录以供新架构使用
      final dllPath = await _extractDllToTemp();
      _addLogMessage('SUCCESS', 'DLL已提取到临时目录');

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
            _statusLevel = 'WARNING';
          });
          // 用户取消，停止日志监控并清理资源
          await _cleanupResources();
          return;
        }

        setState(() {
          _isLoading = true;
          _statusMessage = '正在关闭现有微信进程...';
          _statusLevel = 'INFO';
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
        _statusLevel = 'INFO';
      });

      final launched = await DllInjector.launchWeChat();
      if (!launched) {
        _addLogMessage('ERROR', '微信启动失败，请检查微信安装路径');
        await AppLogger.error('微信启动失败，可能原因：路径错误或微信未安装');
        setState(() {
          _isLoading = false;
          _statusMessage = '微信启动失败';
          _statusLevel = 'ERROR';
        });
        // 停止日志监控并清理资源
        await _cleanupResources();
        // 提示用户检查设置

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
        _statusLevel = 'INFO';
      });

      final windowAppeared = await DllInjector.waitForWeChatWindow(
        maxWaitSeconds: 15,
      );
      if (!windowAppeared) {
        _addLogMessage('ERROR', '等待微信窗口超时，微信可能启动失败');
        await AppLogger.error('等待微信窗口超时');
        setState(() {
          _isLoading = false;
          _statusMessage = '等待微信窗口超时';
          _statusLevel = 'WARNING';
        });
        // 停止日志监控并清理资源
        await _cleanupResources();
        return;
      }

      // 5. 检测微信界面组件，确认窗口加载完成
      _addLogMessage('INFO', '正在检测微信窗口组件，确保界面加载完整');
      setState(() {
        _statusMessage = '检测微信界面组件...';
        _statusLevel = 'INFO';
      });

      final componentsReady =
          await DllInjector.waitForWeChatWindowComponents(maxWaitSeconds: 15);

      if (!componentsReady) {
        _addLogMessage('ERROR', '未检测到微信界面关键组件，微信可能尚未完成加载');
        await AppLogger.error('微信界面组件检测超时');
        setState(() {
          _statusMessage = '微信界面组件未准备好，获取密钥已停止';
          _statusLevel = 'ERROR';
        });
        await _cleanupResources();
        return;
      }

      _addLogMessage('SUCCESS', '微信界面组件已加载完成');
      setState(() {
        _statusMessage = '微信界面组件已就绪，继续注入';
        _statusLevel = 'INFO';
      });


      // 6. 初始化远程Hook控制器（新架构）
      _addLogMessage('INFO', '正在初始化远程Hook控制器...');
      setState(() {
        _statusMessage = '正在初始化远程Hook控制器...';
        _statusLevel = 'INFO';
      });

      // 初始化控制器DLL
      if (!RemoteHookController.initialize(dllPath)) {
        _addLogMessage('ERROR', 'DLL初始化失败');
        await AppLogger.error('远程Hook控制器初始化失败');
        setState(() {
          _statusMessage = 'DLL初始化失败';
          _statusLevel = 'ERROR';
        });
        await _cleanupResources();
        return;
      }

      _addLogMessage('SUCCESS', 'DLL初始化成功');

      // 7. 查找微信主进程PID
      _addLogMessage('INFO', '正在查找微信主进程...');
      final mainPid = DllInjector.findMainWeChatPid();

      if (mainPid == null) {
        _addLogMessage('ERROR', '未找到微信主窗口进程');
        await AppLogger.error('未找到微信主窗口进程');
        setState(() {
          _statusMessage = '未找到微信主窗口';
          _statusLevel = 'ERROR';
        });
        RemoteHookController.dispose();
        await _cleanupResources();
        return;
      }

      _addLogMessage('INFO', '找到微信主进程 PID: $mainPid');

      // 8. 安装远程Hook
      _addLogMessage('INFO', '正在安装远程Hook...');
      setState(() {
        _statusMessage = '正在安装远程Hook...';
        _statusLevel = 'INFO';
      });

      final success = RemoteHookController.installHook(
        targetPid: mainPid,
        onKeyReceived: (keyHex) async {
          await _onKeyReceived(keyHex);
        },
        onStatus: (status, level) {
          // 状态回调: level 0=info, 1=success, 2=error
          final logType = level == 0
              ? 'INFO'
              : (level == 1 ? 'SUCCESS' : 'ERROR');
          _addLogMessage(logType, '[DLL] $status');

          setState(() {
            _statusMessage = status;
            _statusLevel = logType;
          });
        },
      );

      if (success) {
        _addLogMessage('SUCCESS', '远程Hook安装成功！等待密钥获取...');
        await AppLogger.success('远程Hook安装成功，开始等待密钥获取');
        setState(() {
          _isDllInjected = true; // 复用这个状态变量
          _statusMessage = 'Hook已安装！请登录微信...';
          _statusLevel = 'SUCCESS';
        });

        // 设置超时，如果一段时间内没有收到密钥，则停止监听
        _startKeyTimeout();
      } else {
        final error = RemoteHookController.getLastErrorMessage();
        _addLogMessage('ERROR', 'Hook安装失败: $error');
        await AppLogger.error('Hook安装失败: $error');
        setState(() {
          _statusMessage = 'Hook安装失败';
          _statusLevel = 'ERROR';
        });
        RemoteHookController.dispose();
        await _cleanupResources();
      }
    } catch (e, stackTrace) {
      _addLogMessage('ERROR', '获取密钥过程出错: $e');
      await AppLogger.error('获取密钥过程出错', e, stackTrace);
      setState(() {
        _statusMessage = '获取密钥失败: $e';
        _statusLevel = 'ERROR';
      });
      // 出错时停止日志监控并清理资源
      await _cleanupResources();
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 提取DLL到临时目录
  Future<String> _extractDllToTemp() async {
    try {
      // 从assets加载DLL
      final dllData = await rootBundle.load('assets/dll/wx_key.dll');

      // 保存到临时目录（使用唯一文件名避免被锁定）
      final tempDir = Directory.systemTemp;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final dllPath = path.join(
        tempDir.path,
        'wx_key_controller_$timestamp.dll',
      );
      final dllFile = File(dllPath);

      // 写入新文件
      await dllFile.writeAsBytes(dllData.buffer.asUint8List(), flush: true);

      AppLogger.success('DLL已提取到: $dllPath');

      // 异步清理旧的DLL文件（不影响当前操作）
      _cleanupOldDllFiles(tempDir);

      return dllPath;
    } catch (e, stackTrace) {
      AppLogger.error('提取DLL失败', e, stackTrace);
      rethrow;
    }
  }

  /// 清理旧的DLL文件
  Future<void> _cleanupOldDllFiles(Directory tempDir) async {
    try {
      await for (final entity in tempDir.list()) {
        if (entity is File) {
          final fileName = path.basename(entity.path);
          // 删除所有旧的 wx_key_controller_*.dll 文件
          if (fileName.startsWith('wx_key_controller_') &&
              fileName.endsWith('.dll')) {
            try {
              // 检查文件是否超过1小时未修改（避免删除正在使用的文件）
              final stat = await entity.stat();
              final age = DateTime.now().difference(stat.modified);
              if (age.inHours >= 1) {
                await entity.delete();
                AppLogger.info('已清理旧DLL: $fileName');
              }
            } catch (e) {
              // 忽略单个文件删除失败（可能仍在使用）
            }
          }
        }
      }
    } catch (e) {
      // 清理失败不影响主流程
      AppLogger.warning('清理旧DLL文件失败: $e');
    }
  }

  /// 复制密钥到剪贴板
  Future<void> _copyKeyToClipboard(String key) async {
    try {
      await Clipboard.setData(ClipboardData(text: key));
      _addLogMessage('SUCCESS', '密钥已复制到剪贴板');
      await AppLogger.success('密钥已复制到剪贴板');
    } catch (e) {
      _addLogMessage('ERROR', '复制失败: $e');
      await AppLogger.error('复制密钥失败: $e');
    }
  }

  /// 获取图片密钥（XOR和AES）
  Future<void> _getImageKeys() async {
    if (_isLoading) {
      _addLogMessage('WARNING', '正在提取数据库密钥，请稍后再获取图片密钥');
      await AppLogger.warning('数据库密钥提取期间无法获取图片密钥');
      if (mounted) {
        setState(() {
          _statusMessage = '数据库密钥提取中，请稍候再试图片密钥';
          _statusLevel = 'WARNING';
        });
      }
      return;
    }

    if (_isGettingImageKey) {
      return;
    }

    if (!_isWechatRunning) {
      _addLogMessage('WARNING', '请先启动微信');
      await AppLogger.warning('请先启动微信后再获取图片密钥');
      if (mounted) {
        setState(() {
          _statusMessage = '请先启动微信，再尝试获取图片密钥';
          _statusLevel = 'WARNING';
        });
      }
      return;
    }

    setState(() {
      _isGettingImageKey = true;
      _statusMessage = '正在获取图片密钥...';
      _statusLevel = 'INFO';
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
          content:
              '无法自动找到微信缓存目录。\n\n通常位于：\nDocuments\\xwechat_files\\你的账号ID\n\n是否手动选择目录？',
          confirmText: '手动选择',
          cancelText: '取消',
        );

        if (!shouldSelectManually) {
          _addLogMessage('WARNING', '用户取消手动选择');
          await AppLogger.info('用户取消手动选择微信缓存目录');
          setState(() {
            _isGettingImageKey = false;
            _statusMessage = '已取消获取图片密钥';
            _statusLevel = 'WARNING';
          });
          return;
        }

        // 让用户选择目录
        final selectedDirectory =
            await ImageKeyService.selectWeChatCacheDirectory();

        if (selectedDirectory == null || selectedDirectory.isEmpty) {
          _addLogMessage('WARNING', '未选择目录');
          await AppLogger.info('用户未选择微信缓存目录');
          setState(() {
            _isGettingImageKey = false;
            _statusMessage = '未选择目录，已取消获取图片密钥';
            _statusLevel = 'WARNING';
          });
          return;
        }

        _addLogMessage('INFO', '已选择目录，重新尝试获取密钥...');
        await AppLogger.info('用户选择了目录: $selectedDirectory');

        // 使用选择的目录重新获取
        result = await ImageKeyService.getImageKeys(
          manualDirectory: selectedDirectory,
        );
      }

      if (result.success && result.xorKey != null && result.aesKey != null) {
        final saveSuccess = await KeyStorage.saveImageKeys(
          result.xorKey!,
          result.aesKey!,
        );

        if (saveSuccess) {
          setState(() {
            _imageXorKey = result.xorKey;
            _imageAesKey = result.aesKey;
            _imageKeyTimestamp = DateTime.now();
            _statusMessage = '图片密钥获取成功，可以在下方查看';
            _statusLevel = 'SUCCESS';
          });

          _addLogMessage('SUCCESS', '图片密钥获取成功');
          await AppLogger.success(
            '图片密钥获取成功: XOR=0x${result.xorKey!.toRadixString(16).toUpperCase()}, AES=${result.aesKey}',
          );
        } else {
          _addLogMessage('ERROR', '图片密钥保存失败');
          await AppLogger.error('图片密钥保存失败');
          if (mounted) {
            setState(() {
              _statusMessage = '图片密钥获取成功但保存失败';
              _statusLevel = 'ERROR';
            });
          }
        }
      } else {
        _addLogMessage('ERROR', result.error ?? '图片密钥获取失败');
        await AppLogger.error('图片密钥获取失败: ${result.error}');
        if (mounted) {
          setState(() {
            _statusMessage = result.error ?? '图片密钥获取失败';
            _statusLevel = 'ERROR';
          });
        }
      }
    } catch (e, stackTrace) {
      _addLogMessage('ERROR', '获取图片密钥时出错');
      await AppLogger.error('获取图片密钥时出错', e, stackTrace);
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
                  _statusMessage = '微信已退出，未获取到密钥，请重新尝试';
                  _statusLevel = 'WARNING';
                });
                _addLogMessage('WARNING', '微信已退出，未获取到密钥');
              }
            }
          });
        }

        // 如果已经获取到密钥，不要覆盖状态消息
        if (!_isLoading && !_isGettingImageKey && _extractedKey == null) {
          if (isRunning) {
            if (!_isDllInjected) {
              _statusMessage = _wechatVersion != null
                  ? '检测到微信进程 (版本: $_wechatVersion)'
                  : '检测到微信进程';
            } else {
              _statusMessage = '正在监听密钥，请前往微信登录即可获取密钥';
            }
            _statusLevel = 'INFO';
          } else {
            _statusMessage = _wechatVersion != null
                ? '未检测到微信进程 (记录的版本: $_wechatVersion)'
                : '未检测到微信进程';
            _statusLevel = 'INFO';
          }
        }
      });
    }
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

  Widget _buildStatusBanner({bool emphasize = false}) {
    final bool isLoading = _isLoading;
    final bool isImageLoading = _isGettingImageKey;
    final bool showArrowIndicator = isLoading || isImageLoading;
    final _StatusVisual visual = _statusVisual(
      showArrowIndicator ? 'LOADING' : _statusLevel,
    );
    final bannerKey =
        '${visual.stateKey}_${_statusMessage}_${showArrowIndicator ? 1 : 0}_${emphasize ? 1 : 0}_${isImageLoading ? 1 : 0}';
    final double horizontalPadding = emphasize ? 28 : 20;
    final double verticalPadding = emphasize ? 26 : 18;
    final borderRadius = BorderRadius.circular(emphasize ? 22 : 16);
    final textColor = emphasize ? Colors.grey.shade900 : Colors.grey.shade800;
    const double indicatorDiameter = 58;
    final double indicatorSize = indicatorDiameter;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      decoration: BoxDecoration(
        color: visual.background,
        borderRadius: borderRadius,
        border: Border.all(color: visual.border),
        boxShadow: [
          BoxShadow(
            color: visual.shadow,
            blurRadius: showArrowIndicator ? 24 : 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: Row(
          key: ValueKey(bannerKey),
          crossAxisAlignment: emphasize
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            _buildStatusIndicator(
              visual: visual,
              showArrowIndicator: showArrowIndicator,
              emphasize: emphasize,
              size: indicatorSize,
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _statusMessage,
                    style: TextStyle(
                      fontSize: emphasize ? 16 : 14,
                      color: textColor,
                      fontFamily: 'HarmonyOS_SansSC',
                      height: 1.4,
                      fontWeight: emphasize ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  if (isLoading) ...[
                    const SizedBox(height: 6),
                    Text(
                      emphasize
                          ? '\u6b63\u5728\u6267\u884c\u5173\u952e\u6b65\u9aa4\uff0c\u8bf7\u4fdd\u6301\u5fae\u4fe1\u754c\u9762\u9759\u6b62'
                          : '\u6b63\u5728\u8fdb\u884c\u81ea\u52a8\u5904\u7406\uff0c\u8bf7\u7a0d\u5019',
                      style: TextStyle(
                        fontSize: emphasize ? 13 : 12,
                        color: textColor.withOpacity(0.65),
                        fontFamily: 'HarmonyOS_SansSC',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator({
    required _StatusVisual visual,
    required bool showArrowIndicator,
    required bool emphasize,
    required double size,
  }) {
    final Color badgeColor = visual.iconColor;
    final _BadgeGlyphType glyph = _badgeGlyphForVisual(visual);

    Widget buildBadge(CustomPainter foregroundPainter) {
      return SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _CircularBadgeBackgroundPainter(
            color: badgeColor,
            emphasize: emphasize,
          ),
          foregroundPainter: foregroundPainter,
        ),
      );
    }

    if (showArrowIndicator) {
      return AnimatedBuilder(
        animation: _statusBackdropController,
        builder: (_, __) => buildBadge(
          _CircularArrowGlyphPainter(
            progress: _statusBackdropController.value,
            color: badgeColor,
            emphasize: emphasize,
          ),
        ),
      );
    }

    final Duration animationDuration = glyph == _BadgeGlyphType.check
        ? const Duration(milliseconds: 420)
        : const Duration(milliseconds: 360);
    final Curve animationCurve = glyph == _BadgeGlyphType.check
        ? Curves.easeOutCubic
        : Curves.easeOutBack;

    return TweenAnimationBuilder<double>(
      key: ValueKey('${glyph.index}_${emphasize ? 1 : 0}'),
      tween: Tween<double>(begin: 0, end: 1),
      duration: animationDuration,
      curve: animationCurve,
      builder: (_, value, __) => buildBadge(
        _StatusGlyphPainter(
          type: glyph,
          color: badgeColor,
          emphasize: emphasize,
          progress: value,
        ),
      ),
    );
  }

  Widget _buildLoadingTipsCard() {
    final tips = [
      '\u6267\u884c\u671f\u95f4\u8bf7\u4fdd\u6301\u5fae\u4fe1\u5904\u4e8e\u767b\u5f55\u754c\u9762\u6216\u684c\u9762\u524d\u53f0',
      '\u4e0d\u8981\u968f\u610f\u70b9\u51fb\u9f20\u6807\u6216\u952e\u76d8\uff0c\u907f\u514d\u6253\u65ad\u81ea\u52a8\u6d41\u7a0b',
      '\u5982\u82e5\u957f\u65f6\u95f4\u65e0\u54cd\u5e94\uff0c\u53ef\u7b49\u5f85\u63d0\u793a\u6216\u53d6\u6d88\u540e\u91cd\u8bd5',
    ];

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '\u64cd\u4f5c\u63d0\u793a',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade900,
              fontFamily: 'HarmonyOS_SansSC',
            ),
          ),
          const SizedBox(height: 14),
          ...tips.map(
            (tip) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 7, right: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF07c160),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      tip,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                        fontFamily: 'HarmonyOS_SansSC',
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  _StatusVisual _statusVisual(String level) {
    switch (level) {
      case 'SUCCESS':
        return _StatusVisual(
          stateKey: 'success',
          background: const Color(0xFFE8F6EE),
          border: const Color(0xFFCBEBD8),
          iconColor: const Color(0xFF07C160),
          icon: Icons.check_circle_rounded,
          shadow: const Color(0xFF07C160).withOpacity(0.18),
        );
      case 'WARNING':
        return _StatusVisual(
          stateKey: 'warning',
          background: const Color(0xFFFFF7E6),
          border: const Color(0xFFFFE2A8),
          iconColor: const Color(0xFFFFA000),
          icon: Icons.warning_amber_rounded,
          shadow: const Color(0xFFFFC107).withOpacity(0.18),
        );
      case 'ERROR':
        return _StatusVisual(
          stateKey: 'error',
          background: const Color(0xFFFFEEF0),
          border: const Color(0xFFF9C4C8),
          iconColor: const Color(0xFFE53935),
          icon: Icons.error_rounded,
          shadow: const Color(0xFFE53935).withOpacity(0.18),
        );
      case 'LOADING':
        return _StatusVisual(
          stateKey: 'loading',
          background: const Color(0xFFE9F0FF),
          border: const Color(0xFFBFD3FF),
          iconColor: const Color(0xFF3B82F6),
          icon: Icons.more_horiz_rounded,
          shadow: const Color(0xFF3B82F6).withOpacity(0.16),
        );
      default:
        return _StatusVisual(
          stateKey: 'info',
          background: const Color(0xFFF4F6FB),
          border: const Color(0xFFE1E6F5),
          iconColor: const Color(0xFF4C6FFF),
          icon: Icons.info_rounded,
          shadow: const Color(0xFF4C6FFF).withOpacity(0.12),
        );
    }
  }

  _BadgeGlyphType _badgeGlyphForVisual(_StatusVisual visual) {
    switch (visual.stateKey) {
      case 'success':
        return _BadgeGlyphType.check;
      default:
        return _BadgeGlyphType.exclamation;
    }
  }

  Widget _buildSimpleActionButton() {
    final isEnabled = !_isLoading && _wechatVersion != null;

    return Container(
      width: double.infinity,
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: isEnabled
            ? [
                BoxShadow(
                  color: const Color(0xFF07c160).withOpacity(0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
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
    final bool isBusy = _isGettingImageKey;
    final bool canDisplayButton = !_isLoading && !_isDllInjected;
    final String labelText = isBusy ? '正在获取图片密钥...' : '获取图片密钥';

    final button = Container(
      key: const ValueKey('image-key-button'),
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
      child: ElevatedButton(
        onPressed: isBusy ? null : _getImageKeys,
        child: Text(
          labelText,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            fontFamily: 'HarmonyOS_SansSC',
            letterSpacing: 0.3,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue.shade600,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.blue.shade200,
          disabledForegroundColor: Colors.white70,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: canDisplayButton
          ? button
          : const SizedBox.shrink(key: ValueKey('image-key-hidden')),
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
                icon: const Icon(
                  Icons.content_copy_rounded,
                  size: 15,
                  color: Color(0xFF07c160),
                ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
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
        border: Border.all(color: Colors.blue.withOpacity(0.15), width: 1.5),
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
                      onPressed: () => _copyKeyToClipboard(
                        '0x${_imageXorKey!.toRadixString(16).toUpperCase().padLeft(2, '0')}',
                      ),
                      icon: const Icon(
                        Icons.content_copy_rounded,
                        size: 14,
                        color: Colors.blue,
                      ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
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
                      icon: const Icon(
                        Icons.content_copy_rounded,
                        size: 14,
                        color: Colors.blue,
                      ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
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
                    _buildStatusBanner(
                      emphasize: _isLoading || _isGettingImageKey,
                    ),
                    if (_isLoading) ...[
                      const SizedBox(height: 16),
                      _buildLoadingTipsCard(),
                      const SizedBox(height: 16),
                    ] else
                      const SizedBox(height: 20),

                    // 操作按钮 - 未注入时显示，超时或失败时也会重新显示
                    if (!_isDllInjected && !_isLoading)
                      _buildSimpleActionButton(),
                    const SizedBox(height: 20),

                    // 图片密钥获取按钮
                    if (_isWechatRunning)
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
                          children: _logMessages
                              .take(8)
                              .map((log) => _buildLogItem(log))
                              .toList(),
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
