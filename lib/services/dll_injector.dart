import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'key_storage.dart';

class DllInjector {
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

  static bool injectDllByPid(int pid, String dllPath) {

    final hProcess = OpenProcess(PROCESS_ALL_ACCESS, FALSE, pid);
    if (hProcess == 0) {
      return false;
    }
    final remoteMemory = VirtualAllocEx(
        hProcess, nullptr, dllPath.length + 1, MEM_COMMIT, PAGE_READWRITE);
    if (remoteMemory == nullptr) {
      CloseHandle(hProcess);
      return false;
    }

    final dllPathC = dllPath.toNativeUtf8();
    final written = calloc<SIZE_T>();
    try {
      if (WriteProcessMemory(hProcess, remoteMemory, dllPathC,
              dllPath.length + 1, written) ==
          0) {
        VirtualFreeEx(hProcess, remoteMemory, 0, MEM_RELEASE);
        CloseHandle(hProcess);
        return false;
      }
    } finally {
      free(dllPathC);
      free(written);
    }

    final hKernel32 = GetModuleHandle('kernel32.dll'.toNativeUtf16());
    final loadLibraryAddr = GetProcAddress(hKernel32, 'LoadLibraryA'.toNativeUtf8().cast());
    if (loadLibraryAddr == nullptr) {
      VirtualFreeEx(hProcess, remoteMemory, 0, MEM_RELEASE);
      CloseHandle(hProcess);
      return false;
    }

    final hThread = CreateRemoteThread(
        hProcess, nullptr, 0, loadLibraryAddr.cast(), remoteMemory, 0, nullptr);
    if (hThread == 0) {
      VirtualFreeEx(hProcess, remoteMemory, 0, MEM_RELEASE);
      CloseHandle(hProcess);
      return false;
    }

    WaitForSingleObject(hThread, INFINITE);

    VirtualFreeEx(hProcess, remoteMemory, 0, MEM_RELEASE);
    CloseHandle(hThread);
    CloseHandle(hProcess);

    return true;
  }

  static bool injectDll(String processName, String dllPath) {
    if (!File(dllPath).existsSync()) {
      return false;
    }

    final mainPid = findMainWeChatPid();

    if (mainPid == null) {
      return false;
    }

    
    if (injectDllByPid(mainPid, dllPath)) {
      return true;
    } else {
      return false;
    }
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

  static Future<String?> downloadDll(String version) async {
    try {
      final tempDir = Directory.systemTemp;
      final dllPath = path.join(tempDir.path, 'wx_key-$version.dll');
      final dllFile = File(dllPath);
      
      // 先检查本地是否已有该DLL文件
      if (await dllFile.exists()) {
        final fileSize = await dllFile.length();
        // 检查文件大小是否合理（至少1KB，避免损坏的文件）
        if (fileSize > 1024) {
          return dllPath;
        }
        // 文件损坏，删除后重新下载
        await dllFile.delete();
      }
      
      // 本地没有或文件损坏，从GitHub下载
      final url = 'https://github.com/ycccccccy/wx_key/releases/download/dlls/wx_key-$version.dll';
      
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        await dllFile.writeAsBytes(response.bodyBytes);
        return dllPath;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  /// 清除DLL缓存
  /// 删除所有已下载的DLL文件
  /// 返回删除的文件数量
  static Future<int> clearDllCache() async {
    try {
      final tempDir = Directory.systemTemp;
      int count = 0;
      
      // 列出所有wx_key开头的dll文件
      await for (final entity in tempDir.list()) {
        if (entity is File) {
          final fileName = path.basename(entity.path);
          if (fileName.startsWith('wx_key-') && fileName.endsWith('.dll')) {
            try {
              await entity.delete();
              count++;
            } catch (e) {
              // 忽略单个文件删除失败
            }
          }
        }
      }
      
      return count;
    } catch (e) {
      return 0;
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
      
      // 首先尝试从注册表获取路径
      String? wechatPath = _getWeChatPathFromRegistry();
      
      // 如果注册表没找到，尝试常见的默认路径
      if (wechatPath == null || !await File(wechatPath).exists()) {
        final fallbackPaths = [
          r'C:\Program Files\Tencent\WeChat\WeChat.exe',
          r'C:\Program Files (x86)\Tencent\WeChat\WeChat.exe',
          r'C:\Program Files\Tencent\Weixin\Weixin.exe',
          r'C:\Program Files (x86)\Tencent\Weixin\Weixin.exe',
        ];
        
        for (final fallbackPath in fallbackPaths) {
          if (await File(fallbackPath).exists()) {
            wechatPath = fallbackPath;
            break;
          }
        }
      }
      
      if (wechatPath == null || !await File(wechatPath).exists()) {
        return false;
      }
      
      await Process.start(wechatPath, []);
      
      await Future.delayed(const Duration(seconds: 2));
      
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

  static int? findMainWeChatPid() {
    final pids = <int>[];
    
    final enumWindowsProc = Pointer.fromFunction<EnumWindowsProc>(_enumWindowsProc, 0);
    final pidsPtr = calloc<Pointer<Int32>>();
    pidsPtr.value = calloc<Int32>(100); 
    
    try {
      if (EnumWindows(enumWindowsProc, pidsPtr.address) == 0) {
        return null;
      }
      
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
        
        if (title.contains('微信') || title.contains('WeChat')) {
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


