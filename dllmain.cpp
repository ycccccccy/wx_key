#include <Windows.h>
#include <string>
#include <sstream>
#include <iomanip>
#include <iostream>
#include <stdio.h>
#include <Psapi.h>
#include <fstream>

// --- 全局变量 ---
static PVOID g_vehHandlerHandle = nullptr;
static volatile uintptr_t g_targetAddress = 0;
static volatile BYTE g_originalByte = 0x00;
static volatile bool g_isWindowReady = false;
static DWORD g_currentProcessId = 0;

// 日志文件路径
static std::string g_logFilePath;

// --- 辅助函数：将本地编码字符串转换为UTF-8 ---
std::string ConvertToUtf8(const std::string& localStr) {
    if (localStr.empty()) return "";
    
    // 1. 转换为宽字符（UTF-16）
    int wideSize = MultiByteToWideChar(CP_ACP, 0, localStr.c_str(), -1, nullptr, 0);
    if (wideSize <= 0) return localStr;
    
    std::wstring wideStr(wideSize, 0);
    MultiByteToWideChar(CP_ACP, 0, localStr.c_str(), -1, &wideStr[0], wideSize);
    
    // 2. 转换为UTF-8
    int utf8Size = WideCharToMultiByte(CP_UTF8, 0, wideStr.c_str(), -1, nullptr, 0, nullptr, nullptr);
    if (utf8Size <= 0) return localStr;
    
    std::string utf8Str(utf8Size, 0);
    WideCharToMultiByte(CP_UTF8, 0, wideStr.c_str(), -1, &utf8Str[0], utf8Size, nullptr, nullptr);
    
    // 移除末尾的空字符
    if (!utf8Str.empty() && utf8Str.back() == '\0') {
        utf8Str.pop_back();
    }
    
    return utf8Str;
}

// --- 获取临时目录日志文件路径 ---
std::string GetLogFilePath() {
    char tempPath[MAX_PATH];
    GetTempPathA(MAX_PATH, tempPath);
    return std::string(tempPath) + "wx_key_status.log";
}

// --- 日志文件写入函数 ---
void WriteLogToFile(const std::string& message) {
    try {
        std::ofstream logFile;
        logFile.open(g_logFilePath, std::ios::app);
        if (logFile.is_open()) {
            // 转换为UTF-8编码
            std::string utf8Message = ConvertToUtf8(message);
            logFile << utf8Message << std::endl;
            logFile.flush();
            logFile.close();
        }
    } catch (...) {
        // 忽略写入错误
    }
}

// --- 辅助函数：内存读取 ---
bool SafeReadPointer(void* address, void** result) { __try { *result = *(void**)address; return true; } __except (EXCEPTION_EXECUTE_HANDLER) { return false; } }
bool SafeReadDword(void* address, DWORD* result) { __try { *result = *(DWORD*)address; return true; } __except (EXCEPTION_EXECUTE_HANDLER) { return false; } }

/**
 * @brief 后台线程，负责耗时的密钥提取和打印工作。
 * @param lpParam 从异常处理器传来的 pUnsafeData 指针 (RDX的值)。
 */
DWORD WINAPI KeyProcessorThread(LPVOID lpParam)
{
    void* pUnsafeData = lpParam;
    if (pUnsafeData) {
        DWORD keySize = 0;
        void* pKeyBuffer = nullptr;
        // 在这个线程里读取内存
        bool canReadKeySize = SafeReadDword((void*)((uintptr_t)pUnsafeData + 0x10), &keySize);
        bool canReadKeyBuffer = SafeReadPointer((void*)((uintptr_t)pUnsafeData + 0x8), &pKeyBuffer);
        if (canReadKeySize && canReadKeyBuffer && keySize == 32 && pKeyBuffer) {
            std::stringstream ss;
            ss << std::hex << std::setfill('0');
            for (DWORD i = 0; i < keySize; ++i) {
                ss << std::setw(2) << static_cast<int>(((unsigned char*)pKeyBuffer)[i]);
            }
            std::string keyHex = ss.str();

            WriteLogToFile("SUCCESS:密钥获取成功");
            
            // 将密钥写入日志文件
            WriteLogToFile("KEY:" + keyHex);
            
            WriteLogToFile("SUCCESS:密钥已写入日志文件");
        }
    }
    return 0;
}


// --- VEH 异常处理器---
LONG NTAPI VectoredExceptionHandler(PEXCEPTION_POINTERS pExceptionInfo)
{
    if (pExceptionInfo->ExceptionRecord->ExceptionCode == STATUS_BREAKPOINT && (uintptr_t)pExceptionInfo->ExceptionRecord->ExceptionAddress == g_targetAddress)
    {
        PCONTEXT pContext = pExceptionInfo->ContextRecord;
        void* pUnsafeData = (void*)pContext->Rdx; // 1. 立即抓取RDX

        // 2. 立即将耗时工作交给后台线程
        HANDLE hThread = CreateThread(nullptr, 0, KeyProcessorThread, pUnsafeData, 0, nullptr);
        if (hThread) { CloseHandle(hThread); }

        // 3. 立即恢复现场并继续执行
        DWORD oldProtect;
        VirtualProtect((LPVOID)g_targetAddress, 1, PAGE_EXECUTE_READWRITE, &oldProtect);
        *(BYTE*)g_targetAddress = g_originalByte; // 恢复原始字节
        VirtualProtect((LPVOID)g_targetAddress, 1, oldProtect, &oldProtect);

        if (g_vehHandlerHandle) {
            RemoveVectoredExceptionHandler(g_vehHandlerHandle); // 卸载处理器
            g_vehHandlerHandle = nullptr;
        }
        pContext->Rip--; // 修正指令指针
        return EXCEPTION_CONTINUE_EXECUTION; // 让微信线程立即恢复
    }
    return EXCEPTION_CONTINUE_SEARCH;
}

// --- 窗口枚举回调 ---
BOOL CALLBACK EnumWindowsProc(HWND hwnd, LPARAM lParam)
{
    DWORD windowProcessId;
    GetWindowThreadProcessId(hwnd, &windowProcessId);
    if (windowProcessId == g_currentProcessId) { g_isWindowReady = true; return FALSE; } return TRUE;
}

// --- 内存扫描函数 ---
uintptr_t FindPattern(const char* moduleName, const char* pattern, const char* mask)
{
    HMODULE hModule = GetModuleHandleA(moduleName); if (!hModule) return 0; MODULEINFO moduleInfo; GetModuleInformation(GetCurrentProcess(), hModule, &moduleInfo, sizeof(MODULEINFO)); uintptr_t base = (uintptr_t)hModule; uintptr_t end = base + moduleInfo.SizeOfImage; size_t patternLength = strlen(mask); uintptr_t current = base; while (current < end) { MEMORY_BASIC_INFORMATION mbi; if (!VirtualQuery((LPCVOID)current, &mbi, sizeof(mbi))) { break; } if (mbi.State == MEM_COMMIT && !(mbi.Protect & PAGE_NOACCESS) && !(mbi.Protect & PAGE_GUARD)) { for (uintptr_t i = (uintptr_t)mbi.BaseAddress; i < (uintptr_t)mbi.BaseAddress + mbi.RegionSize - patternLength; i++) { bool found = true; for (size_t j = 0; j < patternLength; j++) { if (mask[j] != '?' && pattern[j] != *(char*)(i + j)) { found = false; break; } } if (found) { return i; } } } current = (uintptr_t)mbi.BaseAddress + mbi.RegionSize; } return 0;
}

// --- DLL 主线程 ---
DWORD WINAPI MainThread(HMODULE hModule)
{
    g_currentProcessId = GetCurrentProcessId();
    
    // 初始化日志文件路径
    g_logFilePath = GetLogFilePath();
    
    WriteLogToFile("INFO:DLL注入成功，正在初始化");
    WriteLogToFile("INFO:等待微信界面初始化");
    
    while (!g_isWindowReady) { EnumWindows(EnumWindowsProc, 0); Sleep(500); }
    WriteLogToFile("SUCCESS:微信界面已就绪");

    // 直接使用RVA（此处RVA为4.1.2.11版本的）
    HMODULE hWeixin = GetModuleHandleA("Weixin.dll");
    if (!hWeixin) {
        WriteLogToFile("ERROR:未能获取Weixin.dll模块句柄");
        Sleep(10000); return 0;
    }
    const uintptr_t rva_setCipherKey = 0x4BBBC0;
    uintptr_t setCipherKeyAddr = (uintptr_t)hWeixin + rva_setCipherKey;
    g_targetAddress = setCipherKeyAddr;
    WriteLogToFile("SUCCESS:目标地址计算成功");

    g_vehHandlerHandle = AddVectoredExceptionHandler(1, VectoredExceptionHandler);
    if (g_vehHandlerHandle) {
        WriteLogToFile("SUCCESS:异常处理器安装成功");
        g_originalByte = *(BYTE*)g_targetAddress;
        DWORD oldProtect;
        if (VirtualProtect((LPVOID)g_targetAddress, 1, PAGE_EXECUTE_READWRITE, &oldProtect)) {
            *(BYTE*)g_targetAddress = 0xCC;
            VirtualProtect((LPVOID)g_targetAddress, 1, oldProtect, &oldProtect);
            WriteLogToFile("INFO:Hook已设置，请登录微信");
            WriteLogToFile("WARNING:获取密钥后微信会崩溃，这是正常的");
        }
    }
    else {
        WriteLogToFile("ERROR:安装异常处理器失败");
    }
    return 0;
}

// --- DLL 入口点 ---
BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID lpReserved)
{
    if (ul_reason_for_call == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(hModule);
        HANDLE hThread = CreateThread(nullptr, 0, (LPTHREAD_START_ROUTINE)MainThread, hModule, 0, nullptr);
        if (hThread) { CloseHandle(hThread); }
    }
    return TRUE;
}
