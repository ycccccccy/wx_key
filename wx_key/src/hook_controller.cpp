#define HOOK_EXPORTS

#include <Windows.h>
#include <string>
#include <cstring>
#include <sstream>
#include <iomanip>
#include <memory>
#include <vector>

#include "../include/hook_controller.h"
#include "../include/syscalls.h"
#include "../include/remote_scanner.h"
#include "../include/ipc_manager.h"
#include "../include/remote_hooker.h"
#include "../include/shellcode_builder.h"
#include "../include/string_obfuscator.h"

#pragma execution_character_set("utf-8")

// 全局状态
namespace {
    std::unique_ptr<IPCManager> g_ipcManager;
    std::unique_ptr<RemoteHooker> g_remoteHooker;
    HANDLE g_targetProcess = nullptr;
    std::string g_lastError;
    bool g_initialized = false;
    
    // 数据队列
    CRITICAL_SECTION g_dataLock;
    std::string g_pendingKeyData;
    bool g_hasNewKey = false;
    
    struct StatusMessage {
        std::string message;
        int level;
    };
    std::vector<StatusMessage> g_statusQueue;

    std::string WideToUtf8(const std::wstring& wide) {
        if (wide.empty()) {
            return std::string();
        }
        int sizeNeeded = WideCharToMultiByte(
            CP_UTF8,
            0,
            wide.c_str(),
            static_cast<int>(wide.size()),
            nullptr,
            0,
            nullptr,
            nullptr
        );
        if (sizeNeeded <= 0) {
            return std::string();
        }
        std::string utf8(sizeNeeded, 0);
        WideCharToMultiByte(
            CP_UTF8,
            0,
            wide.c_str(),
            static_cast<int>(wide.size()),
            reinterpret_cast<LPSTR>(&utf8[0]),
            sizeNeeded,
            nullptr,
            nullptr
        );
        return utf8;
    }
    
    // 生成唯一ID
    std::string GenerateUniqueId(DWORD pid) {
        std::stringstream ss;
        ss << std::hex << pid << "_" << GetTickCount64();
        return ss.str();
    }
    
    // 发送状态信息
    void SendStatus(const std::string& message, int level) {
        EnterCriticalSection(&g_dataLock);
        g_statusQueue.push_back({message, level});
        // 限制队列大小
        if (g_statusQueue.size() > 100) {
            g_statusQueue.erase(g_statusQueue.begin());
        }
        LeaveCriticalSection(&g_dataLock);
    }
    
    std::string GetSystemErrorMessage(DWORD errorCode) {
        if (errorCode == 0) {
            return std::string();
        }

        LPWSTR buffer = nullptr;
        DWORD length = FormatMessageW(
            FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
            nullptr,
            errorCode,
            MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
            reinterpret_cast<LPWSTR>(&buffer),
            0,
            nullptr
        );

        std::string message;
        if (length && buffer) {
            std::wstring wideMessage(buffer, length);
            while (!wideMessage.empty() && (wideMessage.back() == L'\r' || wideMessage.back() == L'\n')) {
                wideMessage.pop_back();
            }
            message = WideToUtf8(wideMessage);
        }

        if (buffer) {
            LocalFree(buffer);
        }
        return message;
    }

    std::string FormatWin32Error(const std::string& baseMessage, DWORD errorCode) {
        std::ostringstream oss;
        oss << baseMessage;
        if (errorCode != 0) {
            oss << " (code " << errorCode << ")";
            std::string detail = GetSystemErrorMessage(errorCode);
            if (!detail.empty()) {
                oss << ": " << detail;
            }
        }
        return oss.str();
    }

    std::string FormatNtStatusError(const std::string& baseMessage, NTSTATUS status) {
        std::ostringstream oss;
        oss << baseMessage << " (NTSTATUS 0x"
            << std::uppercase << std::hex << std::setw(8) << std::setfill('0')
            << static_cast<unsigned long>(status) << ")";
        return oss.str();
    }

    // 设置错误信息
    void SetLastError(const std::string& error) {
        g_lastError = error;
        SendStatus(error, 2); // level 2 = error
    }
    // 数据回调处理（从IPC线程调用）
    void OnDataReceived(const SharedKeyData& data) {
        // Validate data
        if (data.dataSize != 32) {
            SendStatus("收到的密钥数据长度不正确", 2);
            return;
        }
        
        // 转换为十六进制字符串
        std::stringstream ss;
        ss << std::hex << std::setfill('0');
        for (DWORD i = 0; i < data.dataSize; i++) {
            ss << std::setw(2) << static_cast<int>(data.keyBuffer[i]);
        }
        
        std::string keyHex = ss.str();
        
        // 存入队列
        EnterCriticalSection(&g_dataLock);
        g_pendingKeyData = keyHex;
        g_hasNewKey = true;
        LeaveCriticalSection(&g_dataLock);
        
        SendStatus("已成功接收到密钥", 1); // level 1 = success
    }
}

// 导出函数
HOOK_API bool InitializeHook(DWORD targetPid) {
    if (g_initialized) {
        SetLastError("Hook已经初始化");
        return false;
    }
    
    // 初始化临界区
    InitializeCriticalSection(&g_dataLock);
    g_hasNewKey = false;
    g_pendingKeyData.clear();
    g_statusQueue.clear();
    
    SendStatus("开始初始化Hook系统...", 0);
    
    // 1. 初始化
    SendStatus("正在初始化系统调用...", 0);
    if (!IndirectSyscalls::Initialize()) {
        DWORD errorCode = GetLastError();
        SetLastError(FormatWin32Error("初始化间接系统调用失败", errorCode));
        return false;
    }
    
    // 2. 打开进程
    SendStatus("正在打开目标进程...", 0);
    
    MY_OBJECT_ATTRIBUTES objAttr;
    memset(&objAttr, 0, sizeof(MY_OBJECT_ATTRIBUTES));
    objAttr.Length = sizeof(MY_OBJECT_ATTRIBUTES);
    
    MY_CLIENT_ID clientId;
    memset(&clientId, 0, sizeof(MY_CLIENT_ID));
    clientId.UniqueProcess = (PVOID)(ULONG_PTR)targetPid;
    
    HANDLE hProcess = NULL;
    NTSTATUS status = IndirectSyscalls::NtOpenProcess(
        &hProcess,
        PROCESS_ALL_ACCESS,
        &objAttr,
        &clientId
    );
    
    g_targetProcess = hProcess;
    
    if (status != STATUS_SUCCESS || !g_targetProcess) {
        SetLastError(FormatNtStatusError("打开目标进程失败", status));
        return false;
    }
    
    // 3. 创建扫描并获取微信版本
    SendStatus("正在检测微信版本...", 0);
    RemoteScanner scanner(g_targetProcess);
    std::string wechatVersion = scanner.GetWeChatVersion();
    
    if (wechatVersion.empty()) {
        SetLastError("获取微信版本失败");
        CloseHandle(g_targetProcess);
        g_targetProcess = nullptr;
        return false;
    }
    
    {
        std::stringstream versionMsg;
        versionMsg << u8"检测到的微信版本: " << wechatVersion;
        SendStatus(versionMsg.str(), 0);
    }
    
    // 4. 获取版本配置
    const WeChatVersionConfig* config = VersionConfigManager::GetConfigForVersion(wechatVersion);
    if (!config) {
        std::string errorMsg = std::string(u8"不支持的微信版本: ") + wechatVersion;
        SetLastError(errorMsg);
        CloseHandle(g_targetProcess);
        g_targetProcess = nullptr;
        return false;
    }
    
    // 5. 扫描函数
    SendStatus("正在扫描目标函数...", 0);
    std::string weixinDll = ObfuscatedStrings::GetWeixinDllName();
    RemoteModuleInfo moduleInfo;
    
    if (!scanner.GetRemoteModuleInfo(weixinDll, moduleInfo)) {
        SetLastError("未找到Weixin.dll模块");
        CloseHandle(g_targetProcess);
        g_targetProcess = nullptr;
        return false;
    }
    
    std::vector<uintptr_t> results = scanner.FindAllPatterns(
        moduleInfo,
        config->pattern.data(),
        config->mask.c_str()
    );
    
    if (results.size() != 1) {
        std::stringstream errorMsg;
        errorMsg << u8"模式匹配失败，找到 " << results.size() << u8" 个结果";
        SetLastError(errorMsg.str());
        CloseHandle(g_targetProcess);
        g_targetProcess = nullptr;
        return false;
    }
    
    uintptr_t targetFunctionAddress = results[0] + config->offset;
    
    {
        std::stringstream addrMsg;
        addrMsg << u8"目标函数地址: 0x" << std::hex << targetFunctionAddress;
        SendStatus(addrMsg.str(), 0);
    }
    
    // 6. 在目标进程中分配数据缓冲区（用于存放密钥）
    SendStatus("正在分配远程数据缓冲区...", 0);
    PVOID remoteDataBuffer = nullptr;
    SIZE_T bufferSize = sizeof(SharedKeyData);
    NTSTATUS allocStatus = IndirectSyscalls::NtAllocateVirtualMemory(
        g_targetProcess,
        &remoteDataBuffer,
        0,
        &bufferSize,
        MEM_COMMIT | MEM_RESERVE,
        PAGE_READWRITE
    );
    
    if (allocStatus != STATUS_SUCCESS || !remoteDataBuffer) {
        SetLastError(FormatNtStatusError("分配远程数据缓冲区失败", allocStatus));
        CloseHandle(g_targetProcess);
        g_targetProcess = nullptr;
        IndirectSyscalls::Cleanup();
        return false;
    }
    
    // 7. 初始化ipc
    SendStatus("正在初始化IPC通信...", 0);
    std::string uniqueId = GenerateUniqueId(targetPid);
    g_ipcManager = std::make_unique<IPCManager>();
    
    if (!g_ipcManager->Initialize(uniqueId)) {
        DWORD ipcError = GetLastError();
        SetLastError(FormatWin32Error("初始化IPC通信失败", ipcError));
        
        // 清理远程缓冲区
        SIZE_T freeSize = 0;
        IndirectSyscalls::NtFreeVirtualMemory(
            g_targetProcess,
            &remoteDataBuffer,
            &freeSize,
            MEM_RELEASE
        );
        
        CloseHandle(g_targetProcess);
        g_targetProcess = nullptr;
        IndirectSyscalls::Cleanup();
        return false;
    }
    
    // 设置远程缓冲区地址
    g_ipcManager->SetRemoteBuffer(g_targetProcess, remoteDataBuffer);
    g_ipcManager->SetDataCallback(OnDataReceived);
    
    if (!g_ipcManager->StartListening()) {
        DWORD ipcError = GetLastError();
        SetLastError(FormatWin32Error("启动IPC监听失败", ipcError));
        g_ipcManager->Cleanup();
        g_ipcManager.reset();
        
        // 清理远程缓冲区
        SIZE_T freeSize = 0;
        IndirectSyscalls::NtFreeVirtualMemory(
            g_targetProcess,
            &remoteDataBuffer,
            &freeSize,
            MEM_RELEASE
        );
        
        CloseHandle(g_targetProcess);
        g_targetProcess = nullptr;
        return false;
    }
    
    // 8. 创建hook
    SendStatus("正在准备安装Hook...", 0);
    g_remoteHooker = std::make_unique<RemoteHooker>(g_targetProcess);
    
    // 9. 配置Shellcode
    ShellcodeConfig shellcodeConfig;
    shellcodeConfig.sharedMemoryAddress = remoteDataBuffer; // 使用远程分配的地址
    shellcodeConfig.eventHandle = nullptr; // 不再使用事件，改用轮询
    shellcodeConfig.trampolineAddress = 0; // 将由RemoteHooker填充
    
    // 10. 安装hook
    SendStatus("正在安装远程Hook...", 0);
    if (!g_remoteHooker->InstallHook(targetFunctionAddress, shellcodeConfig)) {
        DWORD hookError = GetLastError();
        SetLastError(FormatWin32Error("安装Hook失败", hookError));
        g_ipcManager->StopListening();
        g_ipcManager->Cleanup();
        g_ipcManager.reset();
        g_remoteHooker.reset();
        CloseHandle(g_targetProcess);
        g_targetProcess = nullptr;
        return false;
    }
    
    g_initialized = true;
    SendStatus("Hook安装成功，正在等待数据...", 1);
    
    return true;
}

HOOK_API bool CleanupHook() {
    if (!g_initialized) {
        return true;
    }
    
    SendStatus("正在清理Hook...", 0);
    
    // 1. 卸载Hook
    if (g_remoteHooker) {
        g_remoteHooker->UninstallHook();
        g_remoteHooker.reset();
    }
    
    // 2. 停止IPC
    if (g_ipcManager) {
        g_ipcManager->StopListening();
        g_ipcManager->Cleanup();
        g_ipcManager.reset();
    }
    
    // 3. 关闭进程句柄
    if (g_targetProcess) {
        CloseHandle(g_targetProcess);
        g_targetProcess = nullptr;
    }
    
    // 4. 清理系统调用
    IndirectSyscalls::Cleanup();
    
    // 5. 清理临界区和数据队列
    EnterCriticalSection(&g_dataLock);
    g_pendingKeyData.clear();
    g_hasNewKey = false;
    g_statusQueue.clear();
    LeaveCriticalSection(&g_dataLock);
    DeleteCriticalSection(&g_dataLock);
    
    g_initialized = false;
    
    return true;
}

HOOK_API bool PollKeyData(char* keyBuffer, int bufferSize) {
    if (!g_initialized || !keyBuffer || bufferSize < 65) {
        return false;
    }
    
    EnterCriticalSection(&g_dataLock);
    
    if (!g_hasNewKey) {
        LeaveCriticalSection(&g_dataLock);
        return false;
    }
    
    // 复制密钥数据
    size_t copyLen = (g_pendingKeyData.length() < (size_t)(bufferSize - 1)) ? g_pendingKeyData.length() : (bufferSize - 1);
    memcpy(keyBuffer, g_pendingKeyData.c_str(), copyLen);
    keyBuffer[copyLen] = '\0';
    g_hasNewKey = false;
    g_pendingKeyData.clear();
    
    LeaveCriticalSection(&g_dataLock);
    
    return true;
}

HOOK_API bool GetStatusMessage(char* statusBuffer, int bufferSize, int* outLevel) {
    if (!g_initialized || !statusBuffer || bufferSize < 256 || !outLevel) {
        return false;
    }
    
    EnterCriticalSection(&g_dataLock);
    
    if (g_statusQueue.empty()) {
        LeaveCriticalSection(&g_dataLock);
        return false;
    }
    
    // 取出第一条状态消息
    StatusMessage msg = g_statusQueue.front();
    g_statusQueue.erase(g_statusQueue.begin());
    
    LeaveCriticalSection(&g_dataLock);
    
    // 复制到输出缓冲区
    size_t copyLen = (msg.message.length() < (size_t)(bufferSize - 1)) ? msg.message.length() : (bufferSize - 1);
    memcpy(statusBuffer, msg.message.c_str(), copyLen);
    statusBuffer[copyLen] = '\0';
    *outLevel = msg.level;
    
    return true;
}

HOOK_API const char* GetLastErrorMsg() {
    return g_lastError.c_str();
}

