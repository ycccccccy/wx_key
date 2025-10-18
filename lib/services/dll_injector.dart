import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

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

  static String? getWeChatDirectory() {
    const wechatPath = r'C:\Program Files\Tencent\Weixin\Weixin.exe';
    final wechatFile = File(wechatPath);
    
    if (wechatFile.existsSync()) {
      return path.dirname(wechatPath);
    }
    
    return null;
  }

  static String? getWeChatVersion() {
    try {
      final wechatDir = getWeChatDirectory();
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
      final url = 'https://github.com/ycccccccy/wx_key/releases/download/dlls/wx_key-$version.dll';
      
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final tempDir = Directory.systemTemp;
        final dllPath = path.join(tempDir.path, 'wx_key-$version.dll');
        final dllFile = File(dllPath);
        
        await dllFile.writeAsBytes(response.bodyBytes);
        return dllPath;
      } else {
        return null;
      }
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
      const wechatPath = r'C:\Program Files\Tencent\Weixin\Weixin.exe';
      final wechatFile = File(wechatPath);
      
      if (!await wechatFile.exists()) {
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


