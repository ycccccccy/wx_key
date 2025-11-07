#ifndef IPC_MANAGER_H
#define IPC_MANAGER_H

#include <Windows.h>
#include <string>
#include <functional>

// 共享内存数据结构
#pragma pack(push, 1)
struct SharedKeyData {
    DWORD dataSize;           // 数据大小
    BYTE keyBuffer[32];       // 密钥数据（最大32字节）
    DWORD timestamp;          // 时间戳
    DWORD processId;          // 源进程ID
};
#pragma pack(pop)

// IPC管理器类（轮询模式 - 用于远程进程缓冲区读取）
class IPCManager {
public:
    IPCManager();
    ~IPCManager();
    
    // 初始化IPC（控制器端 - 轮询模式）
    bool Initialize(const std::string& uniqueId);
    
    // 设置远程缓冲区地址（目标进程中的地址）
    void SetRemoteBuffer(HANDLE hProcess, PVOID remoteBufferAddr);
    
    // 清理资源
    void Cleanup();
    
    // 设置数据接收回调
    void SetDataCallback(std::function<void(const SharedKeyData&)> callback);
    
    // 启动监听线程（轮询远程缓冲区）
    bool StartListening();
    
    // 停止监听线程
    void StopListening();
    
    // 获取共享内存地址（用于传递给Shellcode）
    PVOID GetSharedMemoryAddress() const;
    
    // 获取事件句柄（用于传递给Shellcode）
    HANDLE GetEventHandle() const;
    
    // 获取共享内存名称
    std::string GetSharedMemoryName() const { return sharedMemoryName; }
    
    // 获取事件名称
    std::string GetEventName() const { return eventName; }

private:
    std::string uniqueId;
    std::string sharedMemoryName;
    std::string eventName;
    
    HANDLE hMapFile;
    HANDLE hEvent;
    PVOID pSharedMemory;
    
    // 远程进程轮询相关
    HANDLE hTargetProcess;
    PVOID pRemoteBuffer;
    DWORD lastTimestamp;
    
    HANDLE hListeningThread;
    volatile bool shouldStopListening;
    
    std::function<void(const SharedKeyData&)> dataCallback;
    
    // 监听线程函数（轮询模式）
    static DWORD WINAPI ListeningThreadProc(LPVOID lpParam);
    void ListeningLoop();
};

#endif // IPC_MANAGER_H

