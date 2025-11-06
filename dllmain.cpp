#include <Windows.h>
#include <string>
#include <sstream>
#include <iomanip>
#include <iostream>
#include <fstream>
#include <Psapi.h>
#include <vector>

#pragma comment(lib, "Psapi.lib")
#pragma comment(lib, "version.lib") 

#pragma region Globals and Helpers
static PVOID g_vehHandlerHandle = nullptr;
static volatile uintptr_t g_targetAddress = 0;
static volatile BYTE g_originalByte = 0x00;
static volatile bool g_isWindowReady = false;
static DWORD g_currentProcessId = 0;
static std::string g_logFilePath;

// 将本地编码字符串转换为UTF-8
std::string ConvertToUtf8(const std::string& localStr) {
    if (localStr.empty()) return "";
    int wideSize = MultiByteToWideChar(CP_ACP, 0, localStr.c_str(), -1, nullptr, 0);
    if (wideSize <= 0) return localStr;
    std::wstring wideStr(wideSize, 0);
    MultiByteToWideChar(CP_ACP, 0, localStr.c_str(), -1, &wideStr[0], wideSize);
    int utf8Size = WideCharToMultiByte(CP_UTF8, 0, wideStr.c_str(), -1, nullptr, 0, nullptr, nullptr);
    if (utf8Size <= 0) return localStr;
    std::string utf8Str(utf8Size, 0);
    WideCharToMultiByte(CP_UTF8, 0, wideStr.c_str(), -1, &utf8Str[0], utf8Size, nullptr, nullptr);
    if (!utf8Str.empty() && utf8Str.back() == '\0') {
        utf8Str.pop_back();
    }
    return utf8Str;
}

// 获取日志文件路径
std::string GetLogFilePath() {
    char tempPath[MAX_PATH];
    GetTempPathA(MAX_PATH, tempPath);
    return std::string(tempPath) + "wx_key_status.log";
}

// 写入日志到文件
void WriteLogToFile(const std::string& message) {
    try {
        std::ofstream logFile;
        logFile.open(g_logFilePath, std::ios::app);
        if (logFile.is_open()) {
            std::string utf8Message = ConvertToUtf8(message);
            logFile << utf8Message << std::endl;
        }
    }
    catch (...) {}
}

// 内存操作函数
bool SafeReadPointer(void* address, void** result) { __try { *result = *(void**)address; return true; } __except (EXCEPTION_EXECUTE_HANDLER) { return false; } }
bool SafeReadDword(void* address, DWORD* result) { __try { *result = *(DWORD*)address; return true; } __except (EXCEPTION_EXECUTE_HANDLER) { return false; } }
bool SafeReadMemory(const void* src, void* dest, size_t size) { __try { memcpy(dest, src, size); return true; } __except (EXCEPTION_EXECUTE_HANDLER) { return false; } }

// 获取微信版本号
std::string GetWeChatVersion() {
    HMODULE hWeixin = GetModuleHandleA("Weixin.dll");
    if (!hWeixin) return "";

    WCHAR modulePath[MAX_PATH];
    if (GetModuleFileNameW(hWeixin, modulePath, MAX_PATH) == 0) return "";

    DWORD handle = 0;
    DWORD versionSize = GetFileVersionInfoSizeW(modulePath, &handle);
    if (versionSize == 0) return "";

    std::vector<BYTE> versionData(versionSize);
    if (!GetFileVersionInfoW(modulePath, handle, versionSize, versionData.data())) return "";

    VS_FIXEDFILEINFO* fileInfo = nullptr;
    UINT fileInfoSize = 0;
    if (VerQueryValueW(versionData.data(), L"\\", (LPVOID*)&fileInfo, &fileInfoSize) && fileInfo) {
        DWORD major = HIWORD(fileInfo->dwProductVersionMS);
        DWORD minor = LOWORD(fileInfo->dwProductVersionMS);
        DWORD build = HIWORD(fileInfo->dwProductVersionLS);
        DWORD revision = LOWORD(fileInfo->dwProductVersionLS);

        std::stringstream ss;
        ss << major << "." << minor << "." << build << "." << revision;
        return ss.str();
    }
    return "";
}

// 密钥处理线程
DWORD WINAPI KeyProcessorThread(LPVOID lpParam) {
    void* pUnsafeData = lpParam;
    if (pUnsafeData) {
        DWORD keySize = 0;
        void* pKeyBuffer = nullptr;
        bool canReadKeySize = SafeReadDword((void*)((uintptr_t)pUnsafeData + 0x10), &keySize);
        bool canReadKeyBuffer = SafeReadPointer((void*)((uintptr_t)pUnsafeData + 0x8), &pKeyBuffer);
        if (canReadKeySize && canReadKeyBuffer && keySize == 32 && pKeyBuffer) {
            std::stringstream ss;
            ss << std::hex << std::setfill('0');
            BYTE localKeyBuffer[32];
            if (SafeReadMemory(pKeyBuffer, localKeyBuffer, 32)) {
                for (DWORD i = 0; i < keySize; ++i) {
                    ss << std::setw(2) << static_cast<int>(localKeyBuffer[i]);
                }
                std::string keyHex = ss.str();
                WriteLogToFile("SUCCESS: 密钥获取成功");
                WriteLogToFile("KEY:" + keyHex);
            }
            else {
                WriteLogToFile("ERROR: 读取最终密钥缓冲区时发生内存访问异常");
            }
        }
        else {
            WriteLogToFile("ERROR: 密钥结构不符合预期或指针读取失败");
        }
    }
    return 0;
}

// VEH 异常处理器
LONG NTAPI VectoredExceptionHandler(PEXCEPTION_POINTERS pExceptionInfo) {
    if (pExceptionInfo->ExceptionRecord->ExceptionCode == STATUS_BREAKPOINT && (uintptr_t)pExceptionInfo->ExceptionRecord->ExceptionAddress == g_targetAddress) {
        PCONTEXT pContext = pExceptionInfo->ContextRecord;
        void* pUnsafeData = (void*)pContext->Rdx;
        HANDLE hThread = CreateThread(nullptr, 0, KeyProcessorThread, pUnsafeData, 0, nullptr);
        if (hThread) { CloseHandle(hThread); }

        DWORD oldProtect;
        VirtualProtect((LPVOID)g_targetAddress, 1, PAGE_EXECUTE_READWRITE, &oldProtect);
        *(BYTE*)g_targetAddress = g_originalByte;
        VirtualProtect((LPVOID)g_targetAddress, 1, oldProtect, &oldProtect);

        if (g_vehHandlerHandle) {
            RemoveVectoredExceptionHandler(g_vehHandlerHandle);
            g_vehHandlerHandle = nullptr;
        }
        pContext->Rip--;
        return EXCEPTION_CONTINUE_EXECUTION;
    }
    return EXCEPTION_CONTINUE_SEARCH;
}

// 等待微信主窗口加载的回调函数
BOOL CALLBACK EnumWindowsProc(HWND hwnd, LPARAM lParam) {
    DWORD windowProcessId;
    GetWindowThreadProcessId(hwnd, &windowProcessId);
    if (windowProcessId == g_currentProcessId) { g_isWindowReady = true; return FALSE; }
    return TRUE;
}

// 特征码扫描函数
std::vector<uintptr_t> FindAllPatterns(const char* moduleName, const char* pattern, const char* mask) {
    std::vector<uintptr_t> results;
    HMODULE hModule = GetModuleHandleA(moduleName);
    if (!hModule) return results;
    MODULEINFO moduleInfo;
    if (!GetModuleInformation(GetCurrentProcess(), hModule, &moduleInfo, sizeof(MODULEINFO))) return results;
    uintptr_t base = (uintptr_t)moduleInfo.lpBaseOfDll;
    uintptr_t end = base + moduleInfo.SizeOfImage;
    size_t patternLength = strlen(mask);
    for (uintptr_t i = base; i < end - patternLength; i++) {
        bool found = true;
        for (size_t j = 0; j < patternLength; j++) {
            unsigned char mem_byte;
            if (!SafeReadMemory((const void*)(i + j), &mem_byte, 1)) {
                found = false;
                break;
            }
            if (mask[j] != '?' && static_cast<unsigned char>(pattern[j]) != mem_byte) {
                found = false;
                break;
            }
        }
        if (found) { results.push_back(i); }
    }
    return results;
}
#pragma endregion Globals and Helpers

// --- DLL 主线程 ---
DWORD WINAPI MainThread(HMODULE hModule) {
    g_currentProcessId = GetCurrentProcessId();
    g_logFilePath = GetLogFilePath();
    std::ofstream ofs(g_logFilePath, std::ofstream::out | std::ofstream::trunc);
    ofs.close();

    WriteLogToFile("INFO: DLL注入成功，正在初始化...");
    while (!g_isWindowReady) { EnumWindows(EnumWindowsProc, 0); Sleep(500); }
    WriteLogToFile("SUCCESS: 微信界面已就绪。");

    // 1. 获取微信版本
    std::string version = GetWeChatVersion();
    if (version.empty()) {
        WriteLogToFile("ERROR: 未能获取微信版本号。");
        return 0;
    }
    WriteLogToFile("INFO: 检测到微信版本: " + version);

    // 2. 根据版本选择特征码
    const char* pattern = nullptr;
    const char* mask = nullptr;
    int offset = 0;

    // 规则匹配：检查版本号是否以特定字符串开头
    if (version.rfind("4.1.4.", 0) == 0) {
        WriteLogToFile("INFO: 应用版本 4.1.4.xx 的特征码...");
        pattern = "\x24\x08\x48\x89\x6c\x24\x10\x48\x89\x74\x00\x18\x48\x89\x7c\x00\x20\x41\x56\x48\x83\xec\x50\x41";
        mask = "xxxxxxxxxx?xxxx?xxxxxxxx";
        offset = -3; // 特征码在函数头后3字节
    }
    else if (version.rfind("4.1.2.", 0) == 0) {
        WriteLogToFile("INFO: 应用版本 4.1.2.xx 的特征码...");
        pattern = "\x24\x50\x48\xc7\x45\x00\xfe\xff\xff\xff\x44\x89\xcf\x44\x89\xc3\x49\x89\xd6\x48\x89\xce\x48\x89";
        mask = "xxxxxxxxxxxxxxxxxxxxxxxx";
        offset = -0xf; // 特征码在函数头后15字节
    }
    else {
        WriteLogToFile("ERROR: 当前微信版本 (" + version + ") 不在支持列表中。");
        return 0;
    }

    // 3. 扫描与定位
    WriteLogToFile("INFO: 开始扫描特征码...");
    std::vector<uintptr_t> results = FindAllPatterns("Weixin.dll", pattern, mask);

    std::stringstream log_ss;
    log_ss << "INFO: 扫描完成，找到 " << results.size() << " 个匹配项。";
    WriteLogToFile(log_ss.str());

    if (results.size() != 1) {
        log_ss.str("");
        log_ss << "ERROR: 特征码匹配失败，找到 " << results.size() << " 个结果。";
        WriteLogToFile(log_ss.str());
        return 0;
    }

    uintptr_t signature_address = results[0];
    g_targetAddress = signature_address + offset; // 使用版本对应的偏移量计算

    log_ss.str("");
    log_ss << "SUCCESS: 目标函数确定，地址 = 0x" << std::hex << g_targetAddress;
    WriteLogToFile(log_ss.str());

    // 4. 执行挂钩
    g_vehHandlerHandle = AddVectoredExceptionHandler(1, VectoredExceptionHandler);
    if (g_vehHandlerHandle) {
        WriteLogToFile("SUCCESS: 异常处理器安装成功");
        DWORD oldProtect;
        if (VirtualProtect((LPVOID)g_targetAddress, 1, PAGE_EXECUTE_READWRITE, &oldProtect)) {
            g_originalByte = *(BYTE*)g_targetAddress;
            *(BYTE*)g_targetAddress = 0xCC;
            VirtualProtect((LPVOID)g_targetAddress, 1, oldProtect, &oldProtect);
            WriteLogToFile("INFO: Hook已设置，请登录微信。");
        }
        else { WriteLogToFile("ERROR: 修改内存保护属性失败。"); }
    }
    else { WriteLogToFile("ERROR: 安装异常处理器失败。"); }

    return 0;
}

// --- DLL 入口点 ---
BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID lpReserved) {
    if (ul_reason_for_call == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(hModule);
        HANDLE hThread = CreateThread(nullptr, 0, (LPTHREAD_START_ROUTINE)MainThread, hModule, 0, nullptr);
        if (hThread) {
            CloseHandle(hThread);
        }
    }
    return TRUE;
}