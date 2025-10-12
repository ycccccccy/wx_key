import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class DllInjector {
  /// Find all process IDs by name
  static List<int> findProcessIds(String processName) {
    final pidsFound = <int>[];
    final processIds = calloc<DWORD>(1024);
    final cb = calloc<DWORD>();

    try {
      if (EnumProcesses(processIds, 1024 * sizeOf<DWORD>(), cb) == 0) {
        print('[-] EnumProcesses failed. Error code: ${GetLastError()}');
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

  /// Check if a process is running by name
  static bool isProcessRunning(String processName) {
    return findProcessIds(processName).isNotEmpty;
  }

  /// Inject DLL into a specific process by PID
  static bool injectDllByPid(int pid, String dllPath) {
    print('\n--- Injecting into PID: $pid ---');

    // 1. Open target process
    final hProcess = OpenProcess(PROCESS_ALL_ACCESS, FALSE, pid);
    if (hProcess == 0) {
      print('[-] OpenProcess failed for PID $pid. Error code: ${GetLastError()}');
      return false;
    }
    print('[+] Got handle to process: $hProcess');

    // 2. Allocate memory for DLL path
    final remoteMemory = VirtualAllocEx(
        hProcess, nullptr, dllPath.length + 1, MEM_COMMIT, PAGE_READWRITE);
    if (remoteMemory == nullptr) {
      print('[-] VirtualAllocEx failed. Error code: ${GetLastError()}');
      CloseHandle(hProcess);
      return false;
    }
    print('[+] Allocated memory at: ${remoteMemory.address.toRadixString(16)}');

    // 3. Write DLL path to remote process
    final dllPathC = dllPath.toNativeUtf8();
    final written = calloc<SIZE_T>();
    try {
      if (WriteProcessMemory(hProcess, remoteMemory, dllPathC,
              dllPath.length + 1, written) ==
          0) {
        print('[-] WriteProcessMemory failed. Error code: ${GetLastError()}');
        VirtualFreeEx(hProcess, remoteMemory, 0, MEM_RELEASE);
        CloseHandle(hProcess);
        return false;
      }
    } finally {
      free(dllPathC);
      free(written);
    }
    print('[+] Wrote DLL path to remote memory.');

    // 4. Get LoadLibraryA address
    final hKernel32 = GetModuleHandle('kernel32.dll'.toNativeUtf16());
    final loadLibraryAddr = GetProcAddress(hKernel32, 'LoadLibraryA'.toNativeUtf8().cast());
    if (loadLibraryAddr == nullptr) {
      print(
          '[-] GetProcAddress for LoadLibraryA failed. Error code: ${GetLastError()}');
      VirtualFreeEx(hProcess, remoteMemory, 0, MEM_RELEASE);
      CloseHandle(hProcess);
      return false;
    }
    print('[+] Found LoadLibraryA at: ${loadLibraryAddr.address.toRadixString(16)}');

    // 5. Create remote thread
    final hThread = CreateRemoteThread(
        hProcess, nullptr, 0, loadLibraryAddr.cast(), remoteMemory, 0, nullptr);
    if (hThread == 0) {
      print('[-] CreateRemoteThread failed. Error code: ${GetLastError()}');
      VirtualFreeEx(hProcess, remoteMemory, 0, MEM_RELEASE);
      CloseHandle(hProcess);
      return false;
    }
    print('[+] CreateRemoteThread succeeded. Waiting for thread to finish...');

    WaitForSingleObject(hThread, INFINITE);
    print('[+] Remote thread finished.');

    // 6. Cleanup
    VirtualFreeEx(hProcess, remoteMemory, 0, MEM_RELEASE);
    CloseHandle(hThread);
    CloseHandle(hProcess);

    print('[*] Injection into PID $pid complete!');
    return true;
  }

  /// Inject DLL into main WeChat process only
  /// [processName] WeChat process name (usually 'Weixin.exe')
  /// [dllPath] Path to the DLL file to inject
  static bool injectDll(String processName, String dllPath) {
    // Check if DLL file exists
    if (!File(dllPath).existsSync()) {
      print('[-] Error: DLL not found at "$dllPath"');
      return false;
    }

    print('[*] Looking for main WeChat process...');
    final mainPid = findMainWeChatPid();

    if (mainPid == null) {
      print('[-] Main WeChat process not found or could not be identified.');
      return false;
    }

    print('[*] Found main WeChat process with PID: $mainPid');
    
    // Inject DLL into main process only
    if (injectDllByPid(mainPid, dllPath)) {
      print('\n[SUCCESS] DLL injected into main WeChat process.');
      return true;
    } else {
      print('\n[FAILED] DLL injection failed for main WeChat process.');
      return false;
    }
  }

  /// Launch WeChat application
  static Future<bool> launchWeChat() async {
    try {
      const wechatPath = r'C:\Program Files\Tencent\Weixin\Weixin.exe';
      final wechatFile = File(wechatPath);
      
      if (!await wechatFile.exists()) {
        print('[-] WeChat executable not found at: $wechatPath');
        return false;
      }
      
      print('[*] Launching WeChat...');
      await Process.start(wechatPath, []);
      
      // Wait a moment for WeChat to start
      await Future.delayed(const Duration(seconds: 2));
      
      // Check if WeChat is now running
      final isRunning = isProcessRunning('Weixin.exe');
      if (isRunning) {
        print('[+] WeChat launched successfully');
        return true;
      } else {
        print('[-] WeChat launch failed or process not detected');
        return false;
      }
    } catch (e) {
      print('[-] Error launching WeChat: $e');
      return false;
    }
  }

  /// Find main WeChat process by window title
  static int? findMainWeChatPid() {
    final pids = <int>[];
    
    // EnumWindows callback function
    final enumWindowsProc = Pointer.fromFunction<EnumWindowsProc>(_enumWindowsProc, 0);
    final pidsPtr = calloc<Pointer<Int32>>();
    pidsPtr.value = calloc<Int32>(100); // Support up to 100 PIDs
    
    try {
      if (EnumWindows(enumWindowsProc, pidsPtr.address) == 0) {
        print('[-] EnumWindows failed. Error code: ${GetLastError()}');
        return null;
      }
      
      // Convert pointer array to list
      for (int i = 0; i < 100; i++) {
        final pid = pidsPtr.value[i];
        if (pid == 0) break;
        pids.add(pid);
      }
      
      if (pids.isNotEmpty) {
        print('[+] Found main WeChat process with PID: ${pids.first}');
        return pids.first;
      } else {
        print('[-] No main WeChat window found');
        return null;
      }
    } finally {
      free(pidsPtr.value);
      free(pidsPtr);
    }
  }

  /// EnumWindows callback function
  static int _enumWindowsProc(int hWnd, int lParam) {
    try {
      // Get process ID from window handle
      final processId = calloc<DWORD>();
      GetWindowThreadProcessId(hWnd, processId);
      
      // Get window title
      final titleLength = GetWindowTextLength(hWnd);
      if (titleLength > 0) {
        final titleBuffer = calloc<Uint16>(titleLength + 1);
        GetWindowText(hWnd, titleBuffer.cast(), titleLength + 1);
        final title = String.fromCharCodes(
          titleBuffer.asTypedList(titleLength + 1).takeWhile((c) => c != 0)
        );
        free(titleBuffer);
        
        // Check if this is the main WeChat window
        if (title.contains('微信') || title.contains('WeChat')) {
          // Get the PID array pointer
          final pidsPtr = Pointer<Pointer<Int32>>.fromAddress(lParam);
          final pids = pidsPtr.value;
          
          // Find first empty slot and add PID
          for (int i = 0; i < 100; i++) {
            if (pids[i] == 0) {
              pids[i] = processId.value;
              break;
            }
          }
        }
      }
      
      free(processId);
      return 1; // Continue enumeration
    } catch (e) {
      print('[-] Error in enumWindowsProc: $e');
      return 1; // Continue enumeration
    }
  }

  /// Get last error message
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


