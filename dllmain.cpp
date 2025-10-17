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

            std::cout << "\n\n======================================================\n";
            std::cout << ">>> 微信数据库密钥获取成功<<<\n";
            std::cout << "======================================================\n";
            std::cout << keyHex << std::endl;
            std::cout << "======================================================\n" << std::endl;

            // 通过命名管道发送密钥给Flutter
            HANDLE hPipe = INVALID_HANDLE_VALUE;
            int retryCount = 0;
            const int maxRetries = 10;

            // 重试连接管道
            while (retryCount < maxRetries && hPipe == INVALID_HANDLE_VALUE) {
                hPipe = CreateFileA(
                    "\\\\.\\pipe\\WeChatKeyPipe",
                    GENERIC_WRITE,
                    0,
                    nullptr,
                    OPEN_EXISTING,
                    FILE_FLAG_WRITE_THROUGH, // 立即写入，不缓冲
                    nullptr
                );

                if (hPipe == INVALID_HANDLE_VALUE) {
                    retryCount++;
                    DWORD error = GetLastError();
                    std::cout << "[-] 管道连接失败 (尝试 " << retryCount << "/" << maxRetries << "), 错误代码: " << error << std::endl;
                    Sleep(100);
                }
            }

            if (hPipe != INVALID_HANDLE_VALUE) {
                DWORD bytesWritten;
                DWORD mode = PIPE_READMODE_MESSAGE;
                SetNamedPipeHandleState(hPipe, &mode, nullptr, nullptr);

                if (WriteFile(hPipe, keyHex.c_str(), keyHex.length(), &bytesWritten, nullptr)) {
                    FlushFileBuffers(hPipe); // 强制刷新缓冲区
                    std::cout << "[+] 密钥已发送" << std::endl;
                }
                else {
                    std::cout << "[-] 发送密钥失败，错误代码: " << GetLastError() << std::endl;
                }
                CloseHandle(hPipe);
            }
            else {
                std::cout << "[-] 无法连接管道，错误代码: " << GetLastError() << std::endl;
                // 如果管道连接失败，至少将密钥写入文件作为备份
                std::ofstream backupFile("C:\\temp\\wechat_key_backup.txt");
                if (backupFile.is_open()) {
                    backupFile << keyHex << std::endl;
                    backupFile.close();
                    std::cout << "[!] 密钥已备份到 C:\\temp\\wechat_key_backup.txt" << std::endl;
                }
            }
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
    if (AllocConsole()) {
        FILE* fp;
        freopen_s(&fp, "CONOUT$", "w", stdout);
        SetConsoleTitleA("WeChat Key");
        std::cout << "[+] 控制台初始化成功" << std::endl;
    }

    std::cout << "[*] 正在等待聊天工具界面初始化" << std::endl;
    while (!g_isWindowReady) { EnumWindows(EnumWindowsProc, 0); Sleep(500); }
    std::cout << "[+] 聊天工具已就绪" << std::endl;

    // 直接使用RVA（此处RVA为4.1.2.11版本的）
    HMODULE hWeixin = GetModuleHandleA("Weixin.dll");
    if (!hWeixin) {
        std::cout << "[-] 致命错误：未能获取模块句柄" << std::endl;
        Sleep(10000); return 0;
    }
    const uintptr_t rva_setCipherKey = 0x4BBBC0;
    uintptr_t setCipherKeyAddr = (uintptr_t)hWeixin + rva_setCipherKey;
    g_targetAddress = setCipherKeyAddr;
    std::cout << "[+] 地址计算成功" << std::endl;

    g_vehHandlerHandle = AddVectoredExceptionHandler(1, VectoredExceptionHandler);
    if (g_vehHandlerHandle) {
        std::cout << "[*] 异常处理器安装成功" << std::endl;
        g_originalByte = *(BYTE*)g_targetAddress;
        DWORD oldProtect;
        if (VirtualProtect((LPVOID)g_targetAddress, 1, PAGE_EXECUTE_READWRITE, &oldProtect)) {
            *(BYTE*)g_targetAddress = 0xCC;
            VirtualProtect((LPVOID)g_targetAddress, 1, oldProtect, &oldProtect);
            std::cout << "[+] 一切就绪，现在登录微信获取密钥" << std::endl;
            std::cout << "[+] 获取密钥后微信会崩溃，这是正常的" << std::endl;
        }
    }
    else {
        std::cout << "[-] 错误：安装异常处理器失败！" << std::endl;
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
