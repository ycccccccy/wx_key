#ifndef REMOTE_SCANNER_H
#define REMOTE_SCANNER_H

#include <Windows.h>
#include <vector>
#include <string>

// 远程进程信息
struct RemoteModuleInfo {
    HMODULE baseAddress;
    SIZE_T imageSize;
    std::string moduleName;
};

// 远程特征码扫描器
class RemoteScanner {
public:
    RemoteScanner(HANDLE hProcess);
    ~RemoteScanner();
    
    // 获取远程进程的模块信息
    bool GetRemoteModuleInfo(const std::string& moduleName, RemoteModuleInfo& outInfo);
    
    // 在远程进程中查找特征码（单个结果）
    uintptr_t FindPattern(const RemoteModuleInfo& moduleInfo, const BYTE* pattern, const char* mask);
    
    // 在远程进程中查找特征码（所有结果）
    std::vector<uintptr_t> FindAllPatterns(const RemoteModuleInfo& moduleInfo, const BYTE* pattern, const char* mask);
    
    // 读取远程内存
    bool ReadRemoteMemory(uintptr_t address, void* buffer, SIZE_T size);
    
    // 获取微信版本号
    std::string GetWeChatVersion();
    
private:
    HANDLE hProcess;
    
    // 本地缓冲区，用于批量读取远程内存
    std::vector<BYTE> scanBuffer;
    
    // 内存匹配辅助函数
    bool MatchPattern(const BYTE* data, const BYTE* pattern, const char* mask, size_t length);
};

// 微信版本配置
struct WeChatVersionConfig {
    std::string version;        // 版本号
    std::vector<BYTE> pattern;  // 特征码
    std::string mask;           // 掩码
    int offset;                 // 偏移量
    
    WeChatVersionConfig(const std::string& ver, const std::vector<BYTE>& pat, const std::string& msk, int off)
        : version(ver), pattern(pat), mask(msk), offset(off) {}
};

// 版本配置管理器
class VersionConfigManager {
public:
    static void InitializeConfigs();
    static const WeChatVersionConfig* GetConfigForVersion(const std::string& version);
    
private:
    static std::vector<WeChatVersionConfig> configs;
    static bool initialized;
};

#endif // REMOTE_SCANNER_H

