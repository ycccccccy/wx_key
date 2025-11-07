#include "../include/ipc_manager.h"
#include "../include/string_obfuscator.h"
#include <Windows.h>
#include <sstream>
#include <iomanip>

IPCManager::IPCManager()
    : hMapFile(nullptr)
    , hEvent(nullptr)
    , pSharedMemory(nullptr)
    , hTargetProcess(nullptr)
    , pRemoteBuffer(nullptr)
    , lastTimestamp(0)
    , hListeningThread(nullptr)
    , shouldStopListening(false)
{
}

IPCManager::~IPCManager() {
    Cleanup();
}

bool IPCManager::Initialize(const std::string& uniqueId) {
    this->uniqueId = uniqueId;
    
    // 生成唯一的共享内存和事件名称
    std::string baseMemName = ObfuscatedStrings::GetSharedMemoryName();
    std::string baseEventName = ObfuscatedStrings::GetEventName();
    
    // 替换{GUID}为实际的uniqueId
    size_t pos = baseMemName.find("{GUID}");
    if (pos != std::string::npos) {
        baseMemName.replace(pos, 6, uniqueId);
    }
    
    pos = baseEventName.find("{GUID}");
    if (pos != std::string::npos) {
        baseEventName.replace(pos, 6, uniqueId);
    }
    
    sharedMemoryName = baseMemName;
    eventName = baseEventName;
    
    // 创建共享内存
    hMapFile = CreateFileMappingA(
        INVALID_HANDLE_VALUE,
        nullptr,
        PAGE_READWRITE,
        0,
        sizeof(SharedKeyData),
        sharedMemoryName.c_str()
    );
    
    if (hMapFile == nullptr) {
        return false;
    }
    
    // 映射共享内存
    pSharedMemory = MapViewOfFile(
        hMapFile,
        FILE_MAP_ALL_ACCESS,
        0,
        0,
        sizeof(SharedKeyData)
    );
    
    if (pSharedMemory == nullptr) {
        CloseHandle(hMapFile);
        hMapFile = nullptr;
        return false;
    }
    
    // 初始化共享内存
    ZeroMemory(pSharedMemory, sizeof(SharedKeyData));
    
    // 创建事件对象（手动重置）
    hEvent = CreateEventA(
        nullptr,
        TRUE,  // 手动重置
        FALSE, // 初始状态非信号
        eventName.c_str()
    );
    
    if (hEvent == nullptr) {
        UnmapViewOfFile(pSharedMemory);
        CloseHandle(hMapFile);
        pSharedMemory = nullptr;
        hMapFile = nullptr;
        return false;
    }
    
    return true;
}

void IPCManager::SetRemoteBuffer(HANDLE hProcess, PVOID remoteBufferAddr) {
    hTargetProcess = hProcess;
    pRemoteBuffer = remoteBufferAddr;
    lastTimestamp = 0;
}

void IPCManager::Cleanup() {
    StopListening();
    
    if (pSharedMemory) {
        UnmapViewOfFile(pSharedMemory);
        pSharedMemory = nullptr;
    }
    
    if (hEvent) {
        CloseHandle(hEvent);
        hEvent = nullptr;
    }
    
    if (hMapFile) {
        CloseHandle(hMapFile);
        hMapFile = nullptr;
    }
}

void IPCManager::SetDataCallback(std::function<void(const SharedKeyData&)> callback) {
    dataCallback = callback;
}

bool IPCManager::StartListening() {
    if (hListeningThread != nullptr) {
        return true; // 已经在监听
    }
    
    shouldStopListening = false;
    hListeningThread = CreateThread(
        nullptr,
        0,
        ListeningThreadProc,
        this,
        0,
        nullptr
    );
    
    return (hListeningThread != nullptr);
}

void IPCManager::StopListening() {
    if (hListeningThread == nullptr) {
        return;
    }
    
    shouldStopListening = true;
    SetEvent(hEvent); // 唤醒等待线程
    
    // 等待线程退出
    WaitForSingleObject(hListeningThread, 5000);
    CloseHandle(hListeningThread);
    hListeningThread = nullptr;
}

PVOID IPCManager::GetSharedMemoryAddress() const {
    return pSharedMemory;
}

HANDLE IPCManager::GetEventHandle() const {
    return hEvent;
}

DWORD WINAPI IPCManager::ListeningThreadProc(LPVOID lpParam) {
    IPCManager* pThis = static_cast<IPCManager*>(lpParam);
    pThis->ListeningLoop();
    return 0;
}

void IPCManager::ListeningLoop() {
    // 轮询模式：周期性读取远程进程中的缓冲区
    while (!shouldStopListening) {
        if (!hTargetProcess || !pRemoteBuffer) {
            Sleep(100);
            continue;
        }
        
        // 从远程进程读取数据
        SharedKeyData keyData;
        ZeroMemory(&keyData, sizeof(keyData));
        
        SIZE_T bytesRead = 0;
        BOOL readResult = ReadProcessMemory(
            hTargetProcess,
            pRemoteBuffer,
            &keyData,
            sizeof(SharedKeyData),
            &bytesRead
        );
        
        if (readResult && bytesRead == sizeof(SharedKeyData)) {
            // 检查是否有新数据（通过timestamp判断）
            if (keyData.dataSize > 0 && 
                keyData.dataSize <= 32 && 
                keyData.timestamp != lastTimestamp &&
                keyData.timestamp != 0) {
                
                // 更新时间戳
                lastTimestamp = keyData.timestamp;
                
                // 调用回调函数
                if (dataCallback) {
                    dataCallback(keyData);
                }
                
                // 清空远程缓冲区（防止重复读取）
                SharedKeyData zeroData;
                ZeroMemory(&zeroData, sizeof(zeroData));
                SIZE_T bytesWritten = 0;
                WriteProcessMemory(
                    hTargetProcess,
                    pRemoteBuffer,
                    &zeroData,
                    sizeof(SharedKeyData),
                    &bytesWritten
                );
            }
        }
        
        // 短暂休眠，避免过度占用CPU（100ms轮询间隔）
        Sleep(100);
    }
}

