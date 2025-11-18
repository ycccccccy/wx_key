import 'dart:ffi';
import 'dart:io';
import 'dart:async';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';
import 'key_storage.dart';
import 'app_logger.dart';

class DllDownloadResult {
  final bool success;
  final String? dllPath;
  final DllDownloadError? error;
  
  DllDownloadResult.success(this.dllPath) 
      : success = true,
        error = null;
  
  DllDownloadResult.failure(this.error) 
      : success = false,
        dllPath = null;
}

enum DllDownloadError {
  networkError,
  versionNotFound,
  fileError,
}

class DllInjector {
  static List<int>? _topWindowHandlesCollector;
  static List<_ChildWindowInfo>? _childWindowCollector;
  static int? _topWindowTargetPid;
  static const List<String> _readyComponentTexts = [
    '聊天',
    '登录',
    '账号',
  ];
  static const List<String> _readyComponentClassMarkers = [
    'WeChat',
    'Weixin',
    'TXGuiFoundation',
    'Qt5',
    'ChatList',
    'MainWnd',
    'BrowserWnd',
    'ListView',
  ];
  static const int _readyChildCountThreshold = 14;

  static List<int> findProcessIds(String processName) {
    final pidsFound = <int>[];
    final processIds = calloc<DWORD>(1024);
    final cb = calloc<DWORD>();

    try {
      if (EnumProcesses(processIds, 1024 * sizeOf<DWORD>(), cb) == 0) {
        return [];
      }

      final count = cb.value ~/ sizeOf<DWORD>();
      for (int i = 0; i < count; i++) {
        final pid = processIds[i];
        if (pid == 0) continue;

        final hProcess = OpenProcess(
            PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, pid);
        if (hProcess != 0) {
          final moduleName = calloc<Uint16>(MAX_PATH);
          try {
            if (GetModuleBaseName(hProcess, 0, moduleName.cast(), MAX_PATH) > 0) {
              final currentName = String.fromCharCodes(
                moduleName.asTypedList(MAX_PATH).takeWhile((c) => c != 0)
              );
              if (currentName.toLowerCase() == processName.toLowerCase()) {
                pidsFound.add(pid);
              }
            }
          } finally {
            free(moduleName);
          }
          CloseHandle(hProcess);
        }
      }
    } finally {
      free(processIds);
      free(cb);
    }
    return pidsFound;
  }

  static bool isProcessRunning(String processName) {
    return findProcessIds(processName).isNotEmpty;
  }

  /// 从注册表获取微信安装路径
  static String? _getWeChatPathFromRegistry() {

    // 1. 首先尝试从卸载信息中查找（最可靠的方法）
    final uninstallPath = _findWeChatFromUninstall();
    if (uninstallPath != null) {
      return uninstallPath;
    }

    // 2. 尝试从 App Paths 查找
    final appPath = _findWeChatFromAppPaths();
    if (appPath != null) {
      return appPath;
    }

    // 3. 尝试腾讯特定注册表路径
    final tencentPath = _findWeChatFromTencentRegistry();
    if (tencentPath != null) {
      return tencentPath;
    }

    return null;
  }

  /// 从卸载信息注册表查找微信
  static String? _findWeChatFromUninstall() {

    final uninstallKeys = [
      r'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
      r'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
    ];

    final rootKeys = [HKEY_LOCAL_MACHINE, HKEY_CURRENT_USER];

    for (final rootKey in rootKeys) {
      for (final uninstallKey in uninstallKeys) {
        final result = _searchUninstallKey(rootKey, uninstallKey);
        if (result != null) {
          return result;
        }
      }
    }

    return null;
  }

  /// 搜索卸载键下的所有子键
  static String? _searchUninstallKey(int rootKey, String keyPath) {
    final phkResult = calloc<HKEY>();

    try {
      if (RegOpenKeyEx(rootKey, keyPath.toNativeUtf16(), 0, KEY_READ, phkResult) != ERROR_SUCCESS) {
        return null;
      }

      var index = 0;
      final subKeyName = calloc<Uint16>(256);

      while (true) {
        final subKeyNameLength = calloc<DWORD>();
        subKeyNameLength.value = 256;

        final result = RegEnumKeyEx(
          phkResult.value,
          index,
          subKeyName.cast(),
          subKeyNameLength,
          nullptr,
          nullptr,
          nullptr,
          nullptr,
        );

        free(subKeyNameLength);

        if (result != ERROR_SUCCESS) {
          break;
        }

        final subKeyNameStr = String.fromCharCodes(
          subKeyName.asTypedList(256).takeWhile((c) => c != 0)
        );

        // 检查是否是微信相关的键
        if (subKeyNameStr.toLowerCase().contains('wechat') ||
            subKeyNameStr.toLowerCase().contains('weixin') ||
            subKeyNameStr.toLowerCase().contains('tencent')) {

          final fullPath = '$keyPath\\$subKeyNameStr';
          final wechatPath = _readInstallLocationFromKey(rootKey, fullPath);

          if (wechatPath != null) {
            free(subKeyName);
            RegCloseKey(phkResult.value);
            return wechatPath;
          }
        }

        index++;
      }

      free(subKeyName);
      RegCloseKey(phkResult.value);
    } catch (e) {
    } finally {
      free(phkResult);
    }

    return null;
  }

  /// 从指定键读取安装位置
  static String? _readInstallLocationFromKey(int rootKey, String keyPath) {
    final phkResult = calloc<HKEY>();

    try {
      if (RegOpenKeyEx(rootKey, keyPath.toNativeUtf16(), 0, KEY_READ, phkResult) != ERROR_SUCCESS) {
        return null;
      }

      // 尝试多个可能的值名称
      final valueNames = [
        'InstallLocation',
        'InstallPath',
        'DisplayIcon',
        'UninstallString',
        'InstallDir',
      ];

      for (final valueName in valueNames) {
        final result = _queryRegistryValue(phkResult.value, valueName);
        if (result != null && result.isNotEmpty) {
          // 处理路径
          var exePath = result;

          // 如果是 UninstallString 或 DisplayIcon，可能包含额外的参数或逗号
          if (valueName == 'UninstallString' || valueName == 'DisplayIcon') {
            exePath = exePath.split(',')[0].trim();
            exePath = exePath.replaceAll('"', '');
          }

          // 如果路径指向 exe 文件
          if (exePath.toLowerCase().endsWith('.exe')) {
            if (File(exePath).existsSync()) {
              RegCloseKey(phkResult.value);
              return exePath;
            }
            // 尝试在同目录找 Weixin.exe 或 WeChat.exe
            final dir = path.dirname(exePath);
            final weixinPath = path.join(dir, 'Weixin.exe');
            if (File(weixinPath).existsSync()) {
              RegCloseKey(phkResult.value);
              return weixinPath;
            }
            final wechatPath = path.join(dir, 'WeChat.exe');
            if (File(wechatPath).existsSync()) {
              RegCloseKey(phkResult.value);
              return wechatPath;
            }
          } else {
            // 如果是目录路径
            final weixinPath = path.join(exePath, 'Weixin.exe');
            if (File(weixinPath).existsSync()) {
              RegCloseKey(phkResult.value);
              return weixinPath;
            }
            final wechatPath = path.join(exePath, 'WeChat.exe');
            if (File(wechatPath).existsSync()) {
              RegCloseKey(phkResult.value);
              return wechatPath;
            }
          }
        }
      }

      RegCloseKey(phkResult.value);
    } catch (e) {
      // 忽略
    } finally {
      free(phkResult);
    }

    return null;
  }

  /// 从 App Paths 查找微信
  static String? _findWeChatFromAppPaths() {

    final appNames = ['WeChat.exe', 'Weixin.exe'];
    final rootKeys = [HKEY_LOCAL_MACHINE, HKEY_CURRENT_USER];

    for (final rootKey in rootKeys) {
      for (final appName in appNames) {
        final keyPath = 'SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\App Paths\\$appName';
        final phkResult = calloc<HKEY>();

        try {
          if (RegOpenKeyEx(rootKey, keyPath.toNativeUtf16(), 0, KEY_READ, phkResult) == ERROR_SUCCESS) {
            final result = _queryRegistryValue(phkResult.value, '');
            RegCloseKey(phkResult.value);

            if (result != null && result.isNotEmpty && File(result).existsSync()) {
              return result;
            }
          }
        } catch (e) {
          // 忽略
        } finally {
          free(phkResult);
        }
      }
    }

    return null;
  }

  /// 从腾讯特定注册表查找微信
  static String? _findWeChatFromTencentRegistry() {

    final keyPaths = [
      r'Software\Tencent\WeChat',
      r'Software\Tencent\bugReport\WeChatWindows',
      r'Software\WOW6432Node\Tencent\WeChat',
      r'Software\Tencent\Weixin',
    ];

    final valueNames = ['InstallPath', 'Install', 'Path', 'InstallDir'];

    for (final keyPath in keyPaths) {
      final phkResult = calloc<HKEY>();

      try {
        // 尝试 HKEY_CURRENT_USER
        if (RegOpenKeyEx(HKEY_CURRENT_USER, keyPath.toNativeUtf16(), 0, KEY_READ, phkResult) == ERROR_SUCCESS) {
          for (final valueName in valueNames) {
            final result = _queryRegistryValue(phkResult.value, valueName);
            if (result != null) {
              RegCloseKey(phkResult.value);
              return result;
            }
          }
          RegCloseKey(phkResult.value);
        }

        // 尝试 HKEY_LOCAL_MACHINE
        if (RegOpenKeyEx(HKEY_LOCAL_MACHINE, keyPath.toNativeUtf16(), 0, KEY_READ, phkResult) == ERROR_SUCCESS) {
          for (final valueName in valueNames) {
            final result = _queryRegistryValue(phkResult.value, valueName);
            if (result != null) {
              RegCloseKey(phkResult.value);
              return result;
            }
          }
          RegCloseKey(phkResult.value);
        }
      } catch (e) {
        // 忽略错误
      } finally {
        free(phkResult);
      }
    }

    return null;
  }

  /// 从注册表键读取字符串值
  static String? _queryRegistryValue(int hKey, String valueName) {
    final lpType = calloc<DWORD>();
    final lpcbData = calloc<DWORD>();

    try {
      // 首先查询数据大小
      if (RegQueryValueEx(hKey, valueName.toNativeUtf16(), nullptr, lpType, nullptr, lpcbData) == ERROR_SUCCESS) {
        if (lpType.value == REG_SZ || lpType.value == REG_EXPAND_SZ) {
          final buffer = calloc<Uint8>(lpcbData.value);

          try {
            if (RegQueryValueEx(hKey, valueName.toNativeUtf16(), nullptr, lpType, buffer, lpcbData) == ERROR_SUCCESS) {
              final result = String.fromCharCodes(
                buffer.cast<Uint16>().asTypedList(lpcbData.value ~/ 2).takeWhile((c) => c != 0)
              );

              // 如果路径不以 .exe 结尾，尝试拼接 Weixin.exe
              if (result.isNotEmpty) {
                if (result.toLowerCase().endsWith('.exe')) {
                  return result;
                } else {
                  final weixinPath = path.join(result, 'Weixin.exe');
                  if (File(weixinPath).existsSync()) {
                    return weixinPath;
                  }
                  return result;
                }
              }
            }
          } finally {
            free(buffer);
          }
        }
      }
    } catch (e) {
      // 忽略错误
    } finally {
      free(lpType);
      free(lpcbData);
    }

    return null;
  }

  static Future<String?> getWeChatDirectory() async {
    // 1. 首先检查用户手动设置的目录
    final savedDirectory = await KeyStorage.getWechatDirectory();
    if (savedDirectory != null) {
      final dir = Directory(savedDirectory);
      if (dir.existsSync()) {
        // 验证目录中是否有 Weixin.exe 或 WeChat.exe
        final weixinPath = path.join(savedDirectory, 'Weixin.exe');
        final wechatPath = path.join(savedDirectory, 'WeChat.exe');
        if (File(weixinPath).existsSync() || File(wechatPath).existsSync()) {
          return savedDirectory;
        }
      }
      // 保存的目录无效，清除它
      await KeyStorage.clearWechatDirectory();
    }

    // 2. 尝试从注册表获取路径
    final wechatPath = _getWeChatPathFromRegistry();

    if (wechatPath != null) {
      final wechatFile = File(wechatPath);
      if (wechatFile.existsSync()) {
        final directory = path.dirname(wechatPath);
        return directory;
      }
    }

    // 3. 尝试多个盘符的常见路径
    final drives = ['C', 'D', 'E', 'F'];
    final commonPaths = [
      r'\Program Files\Tencent\WeChat\WeChat.exe',
      r'\Program Files (x86)\Tencent\WeChat\WeChat.exe',
      r'\Program Files\Tencent\Weixin\Weixin.exe',
      r'\Program Files (x86)\Tencent\Weixin\Weixin.exe',
    ];

    for (final drive in drives) {
      for (final commonPath in commonPaths) {
        final fullPath = '$drive:$commonPath';
        final wechatFile = File(fullPath);
        if (wechatFile.existsSync()) {
          final directory = path.dirname(fullPath);
          return directory;
        }
      }
    }

    return null;
  }

  static Future<String?> getWeChatVersion() async {
    try {
      final wechatDir = await getWeChatDirectory();
      if (wechatDir == null) return null;

      final dir = Directory(wechatDir);
      final entities = dir.listSync();

      for (var entity in entities) {
        if (entity is Directory) {
          final dirName = path.basename(entity.path);
          final versionRegex = RegExp(r'^4\.\d+\.\d+\.\d+$');
          if (versionRegex.hasMatch(dirName)) {
            return dirName;
          }
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }




  /// 手动选择DLL文件
  static Future<String?> selectDllFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: '请选择DLL文件',
        type: FileType.custom,
        allowedExtensions: ['dll'],
      );

      if (result != null && result.files.isNotEmpty) {
        final file = File(result.files.first.path!);
        if (await file.exists()) {
          return result.files.first.path;
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }



  static bool killWeChatProcesses() {
    try {
      final pids = findProcessIds('Weixin.exe');

      if (pids.isEmpty) {
        return true;
      }

      for (var pid in pids) {
        final hProcess = OpenProcess(PROCESS_TERMINATE, FALSE, pid);
        if (hProcess != 0) {
          TerminateProcess(hProcess, 0);
          CloseHandle(hProcess);
        }
      }

      Future.delayed(const Duration(seconds: 1));
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> launchWeChat() async {
    try {
      String? wechatPath;

      // 优先使用用户设置的微信目录
      final wechatDir = await getWeChatDirectory();
      if (wechatDir != null) {
        final weixinPath = path.join(wechatDir, 'Weixin.exe');
        final wechatExePath = path.join(wechatDir, 'WeChat.exe');

        if (await File(weixinPath).exists()) {
          wechatPath = weixinPath;
        } else if (await File(wechatExePath).exists()) {
          wechatPath = wechatExePath;
        }
      }

      // 如果用户设置的目录无效，尝试从注册表获取路径
      if (wechatPath == null) {
        wechatPath = _getWeChatPathFromRegistry();
      }

      // 如果注册表也没找到，尝试常见的默认路径
      if (wechatPath == null || !await File(wechatPath).exists()) {
        final drives = ['C', 'D', 'E', 'F'];
        final pathPatterns = [
          r'\Program Files\Tencent\WeChat\WeChat.exe',
          r'\Program Files (x86)\Tencent\WeChat\WeChat.exe',
          r'\Program Files\Tencent\Weixin\Weixin.exe',
          r'\Program Files (x86)\Tencent\Weixin\Weixin.exe',
        ];

        for (final drive in drives) {
          for (final pattern in pathPatterns) {
            final fullPath = '$drive:$pattern';
            if (await File(fullPath).exists()) {
              wechatPath = fullPath;
              break;
            }
          }
          if (wechatPath != null && await File(wechatPath).exists()) {
            break;
          }
        }
      }

      if (wechatPath == null || !await File(wechatPath).exists()) {
        return false;
      }


      // 启动微信进程
      // ignore: unused_local_variable
      final process = await Process.start(
        wechatPath,
        [],
        mode: ProcessStartMode.detached,
      );


      // 等待进程启动
      await Future.delayed(const Duration(seconds: 2));

      // 检查微信进程是否在运行
      final isRunning = isProcessRunning('Weixin.exe');
      if (isRunning) {
        return true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  static Future<bool> waitForWeChatWindow({int maxWaitSeconds = 10}) async {

    for (int i = 0; i < maxWaitSeconds * 2; i++) {
      await Future.delayed(const Duration(milliseconds: 500));

      final mainPid = findMainWeChatPid();
      if (mainPid != null) {
        return true;
      }
    }

    return false;
  }

  static Future<bool> waitForWeChatWindowComponents({int maxWaitSeconds = 25}) async {
    final deadline = DateTime.now().add(Duration(seconds: maxWaitSeconds));
    int attemptCount = 0;

    while (DateTime.now().isBefore(deadline)) {
      attemptCount++;
      final mainPid = findMainWeChatPid();
      if (mainPid == null) {
        AppLogger.info('第$attemptCount次检测: 未找到微信主窗口PID');
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }

      AppLogger.info('第$attemptCount次检测: 找到微信主窗口PID=$mainPid');
      final handles = _findWechatWindowHandles(targetPid: mainPid);

      if (handles.isEmpty) {
        AppLogger.warning('第$attemptCount次检测: 未枚举到微信窗口句柄');
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }

      AppLogger.info('第$attemptCount次检测: 找到${handles.length}个微信窗口句柄');

      for (final handle in handles) {
        final children = _collectChildWindowInfos(handle);
        _logWechatComponentSnapshot(handle, children);

        if (_hasReadyComponents(children)) {
          AppLogger.success('检测到微信界面组件已加载完毕 (窗口句柄: $handle, 子窗口数: ${children.length})');
          return true;
        }
      }

      await Future.delayed(const Duration(milliseconds: 500));
    }

    AppLogger.warning('等待微信界面组件超时(已等待${maxWaitSeconds}秒)，但窗口可能已就绪');
    return true;
  }

  static List<int> _findWechatWindowHandles({required int targetPid}) {
    final handles = <int>[];
    _topWindowHandlesCollector = handles;
    _topWindowTargetPid = targetPid;
    EnumWindows(
      Pointer.fromFunction<EnumWindowsProc>(_enumWechatTopWindowProc, 0),
      0,
    );
    _topWindowHandlesCollector = null;
    _topWindowTargetPid = null;
    return handles;
  }

  static int _enumWechatTopWindowProc(int hWnd, int lParam) {
    final collector = _topWindowHandlesCollector;
    final targetPid = _topWindowTargetPid;
    if (collector == null) {
      return 0;
    }

    if (IsWindowVisible(hWnd) == 0) {
      return 1;
    }

    final titleLen = GetWindowTextLength(hWnd);
    if (titleLen == 0) {
      return 1;
    }

    final titleBuffer = calloc<Uint16>(titleLen + 1);
    GetWindowText(hWnd, titleBuffer.cast(), titleLen + 1);
    final title = String.fromCharCodes(
      titleBuffer.cast<Uint16>().asTypedList(titleLen + 1).takeWhile((c) => c != 0),
    );
    free(titleBuffer);

    final normalizedTitle = title.trim();
    final normalizedTitleLower = normalizedTitle.toLowerCase();
    final isWeChatTitle = normalizedTitle == '微信' ||
        normalizedTitleLower == 'wechat' ||
        normalizedTitleLower == 'weixin';
    if (!isWeChatTitle) {
      return 1;
    }

    final pidPtr = calloc<DWORD>();
    GetWindowThreadProcessId(hWnd, pidPtr);
    final windowPid = pidPtr.value;
    free(pidPtr);

    if (targetPid != null && windowPid != targetPid) {
      return 1;
    }

    collector.add(hWnd);

    return 1;
  }

  static List<_ChildWindowInfo> _collectChildWindowInfos(int parentHwnd) {
    final children = <_ChildWindowInfo>[];
    _childWindowCollector = children;
    EnumChildWindows(
      parentHwnd,
      Pointer.fromFunction<EnumWindowsProc>(_enumChildWindowProc, 0),
      0,
    );
    _childWindowCollector = null;
    return children;
  }

  static int _enumChildWindowProc(int hWnd, int lParam) {
    final collector = _childWindowCollector;
    if (collector == null) {
      return 0;
    }

    final titleLen = GetWindowTextLength(hWnd);
    final titleBuffer = calloc<Uint16>(titleLen + 1);
    String title = '';
    if (titleLen > 0) {
      GetWindowText(hWnd, titleBuffer.cast(), titleLen + 1);
      title = String.fromCharCodes(
        titleBuffer.cast<Uint16>().asTypedList(titleLen + 1).takeWhile((c) => c != 0),
      );
    }
    free(titleBuffer);

    final classBuffer = calloc<Uint16>(256);
    final classLen = GetClassName(hWnd, classBuffer.cast(), 256);
    final className = classLen > 0
        ? String.fromCharCodes(
            classBuffer.cast<Uint16>().asTypedList(classLen),
          )
        : '';
    free(classBuffer);

    collector.add(_ChildWindowInfo(hWnd, title.trim(), className.trim()));
    return 1;
  }

  static bool _hasReadyComponents(List<_ChildWindowInfo> children) {
    if (children.isEmpty) {
      AppLogger.warning('子窗口列表为空，但仍视为可注入');
      return true;
    }

    var classMatchCount = 0;
    var titleMatchCount = 0;
    var hasValidClassName = false;

    for (final child in children) {
      final normalizedTitle = child.title.replaceAll(RegExp(r'\s+'), '');
      if (normalizedTitle.isNotEmpty) {
        for (final marker in _readyComponentTexts) {
          if (normalizedTitle.contains(marker)) {
            AppLogger.success('检测到关键文本标记: $marker');
            return true;
          }
        }
        titleMatchCount++;
      }

      final className = child.className;
      if (className.isNotEmpty) {
        if (_readyComponentClassMarkers
            .any((marker) => className.contains(marker))) {
          AppLogger.success('检测到关键类名标记: $className');
          return true;
        }
        if (className.length > 5) {
          classMatchCount++;
          hasValidClassName = true;
        }
      }
    }

    if (classMatchCount >= 3 || titleMatchCount >= 2) {
      AppLogger.info('通过计数检测: classMatch=$classMatchCount, titleMatch=$titleMatchCount');
      return true;
    }

    if (children.length >= _readyChildCountThreshold) {
      AppLogger.info('通过子窗口数量检测: ${children.length} >= $_readyChildCountThreshold');
      return true;
    }

    if (hasValidClassName && children.length >= 5) {
      AppLogger.info('放宽条件通过: 有效类名且子窗口数>=5');
      return true;
    }

    AppLogger.warning('组件检测未通过，但可能是窗口结构差异导致');
    return true;
  }

  static void _logWechatComponentSnapshot(
      int hwnd, List<_ChildWindowInfo> children) {
    if (children.isEmpty) {
      AppLogger.info('微信窗口 $hwnd 尚未枚举到子窗口');
      return;
    }

    final snapshot = children
        .take(6)
        .map((child) {
          final title = child.title.isEmpty ? '<空标题>' : child.title;
          final cls = child.className.isEmpty ? '<无类名>' : child.className;
          return '$cls:$title';
        })
        .join(' | ');

    AppLogger.info(
      '微信窗口 $hwnd 子窗口(${children.length}) 快照: $snapshot',
    );
  }


  static int? findMainWeChatPid() {
    final enumWindowsProc = Pointer.fromFunction<EnumWindowsProc>(_enumWindowsProc, 0);
    final pidsPtr = calloc<Pointer<Int32>>();
    pidsPtr.value = calloc<Int32>(100);

    // 初始化数组为0
    for (int i = 0; i < 100; i++) {
      pidsPtr.value[i] = 0;
    }

    try {
      EnumWindows(enumWindowsProc, pidsPtr.address);

      final pids = <int>[];
      for (int i = 0; i < 100; i++) {
        final pid = pidsPtr.value[i];
        if (pid == 0) break;
        pids.add(pid);
      }

      if (pids.isNotEmpty) {
        return pids.first;
      } else {
        return null;
      }
    } finally {
      free(pidsPtr.value);
      free(pidsPtr);
    }
  }

  static int _enumWindowsProc(int hWnd, int lParam) {
    try {
      final processId = calloc<DWORD>();
      GetWindowThreadProcessId(hWnd, processId);

      final titleLength = GetWindowTextLength(hWnd);
      if (titleLength > 0) {
        final titleBuffer = calloc<Uint16>(titleLength + 1);
        GetWindowText(hWnd, titleBuffer.cast(), titleLength + 1);
        final title = String.fromCharCodes(
          titleBuffer.asTypedList(titleLength + 1).takeWhile((c) => c != 0)
        );
        free(titleBuffer);

        if (title.contains('微信') || title.contains('Weixin')) {
          final pidsPtr = Pointer<Pointer<Int32>>.fromAddress(lParam);
          final pids = pidsPtr.value;
          for (int i = 0; i < 100; i++) {
            if (pids[i] == 0) {
              pids[i] = processId.value;
              break;
            }
          }
        }
      }

      free(processId);
      return 1;
    } catch (e) {
      return 1;
    }
  }

  static String getLastErrorMessage() {
    final errorCode = GetLastError();
    if (errorCode == 0) return '';

    final buffer = calloc<Uint16>(256);
    FormatMessage(
      FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
      nullptr,
      errorCode,
      0,
      buffer.cast(),
      256,
      nullptr,
    );

    final message = String.fromCharCodes(
      buffer.asTypedList(256).takeWhile((c) => c != 0)
    );
    free(buffer);
    return message;
  }
}

class _ChildWindowInfo {
  _ChildWindowInfo(this.hwnd, this.title, this.className);

  final int hwnd;
  final String title;
  final String className;
}
