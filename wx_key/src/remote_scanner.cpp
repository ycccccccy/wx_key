#include "../include/remote_scanner.h"
#include "../include/syscalls.h"
#include "../include/string_obfuscator.h"
#include <Psapi.h>
#include <array>
#include <exception>
#include <sstream>

#pragma comment(lib, "Psapi.lib")
#pragma comment(lib, "version.lib")

// 版本配置管理器静态成员
std::vector<WeChatVersionConfig> VersionConfigManager::configs;
bool VersionConfigManager::initialized = false;

namespace {
    using VersionArray = std::array<int, 4>;

    bool ParseVersionString(const std::string& version, VersionArray& outParts) {
        outParts.fill(0);
        std::stringstream ss(version);
        std::string segment;
        size_t index = 0;

        while (std::getline(ss, segment, '.') && index < outParts.size()) {
            try {
                outParts[index++] = std::stoi(segment);
            } catch (const std::exception&) {
                return false;
            }
        }

        return index > 0;
    }

    int CompareVersions(const VersionArray& lhs, const VersionArray& rhs) {
        for (size_t i = 0; i < lhs.size(); ++i) {
            if (lhs[i] < rhs[i]) return -1;
            if (lhs[i] > rhs[i]) return 1;
        }
        return 0;
    }
}

void VersionConfigManager::InitializeConfigs() {
    if (initialized) return;

    // 微信 4.1.4 及以上配置（含 4.1.4.x、4.1.5.x 等）
    configs.push_back(WeChatVersionConfig(
        ">=4.1.4",
        {0x24, 0x08, 0x48, 0x89, 0x6c, 0x24, 0x10, 0x48, 0x89, 0x74, 0x00, 0x18, 0x48, 0x89, 0x7c, 0x00, 0x20, 0x41, 0x56, 0x48, 0x83, 0xec, 0x50, 0x41},
        "xxxxxxxxxx?xxxx?xxxxxxxx",
        -3
    ));

    // 微信 4.1.4 以下（含 4.1.0-4.1.3 与 4.0.x）的通用配置
    configs.push_back(WeChatVersionConfig(
        "<4.1.4",
        {0x24, 0x50, 0x48, 0xc7, 0x45, 0x00, 0xfe, 0xff, 0xff, 0xff, 0x44, 0x89, 0xcf, 0x44, 0x89, 0xc3, 0x49, 0x89, 0xd6, 0x48, 0x89, 0xce, 0x48, 0x89},
        "xxxxxxxxxxxxxxxxxxxxxxxx",
        -0xf
    ));
    
    initialized = true;
}

const WeChatVersionConfig* VersionConfigManager::GetConfigForVersion(const std::string& version) {
    InitializeConfigs();

    if (configs.size() < 2 || version.empty()) {
        return nullptr;
    }

    VersionArray parsedVersion;
    if (!ParseVersionString(version, parsedVersion)) {
        return nullptr;
    }

    constexpr VersionArray baseline414 = {4, 1, 4, 0};

    if (CompareVersions(parsedVersion, baseline414) >= 0) {
        return &configs[0];
    }

    if ((parsedVersion[0] == 4 && parsedVersion[1] == 1 && parsedVersion[2] < 4) ||
        (parsedVersion[0] == 4 && parsedVersion[1] == 0)) {
        return &configs[1];
    }

    return nullptr;
}

// RemoteScanner实现
RemoteScanner::RemoteScanner(HANDLE hProcess)
    : hProcess(hProcess)
{
    // 预分配扫描缓冲区（2MB）
    scanBuffer.reserve(2 * 1024 * 1024);
}

RemoteScanner::~RemoteScanner() {
}

bool RemoteScanner::GetRemoteModuleInfo(const std::string& moduleName, RemoteModuleInfo& outInfo) {
    // 枚举远程进程的模块
    HMODULE hMods[1024];
    DWORD cbNeeded;
    
    if (!EnumProcessModules(this->hProcess, hMods, sizeof(hMods), &cbNeeded)) {
        return false;
    }
    
    DWORD moduleCount = cbNeeded / sizeof(HMODULE);
    
    for (DWORD i = 0; i < moduleCount; i++) {
        char szModName[MAX_PATH];
        
        if (GetModuleBaseNameA(this->hProcess, hMods[i], szModName, sizeof(szModName) / sizeof(char))) {
            if (_stricmp(szModName, moduleName.c_str()) == 0) {
                MODULEINFO modInfo;
                if (GetModuleInformation(this->hProcess, hMods[i], &modInfo, sizeof(modInfo))) {
                    outInfo.baseAddress = hMods[i];
                    outInfo.imageSize = modInfo.SizeOfImage;
                    outInfo.moduleName = szModName;
                    return true;
                }
            }
        }
    }
    
    return false;
}

bool RemoteScanner::MatchPattern(const BYTE* data, const BYTE* pattern, const char* mask, size_t length) {
    for (size_t i = 0; i < length; i++) {
        if (mask[i] != '?' && data[i] != pattern[i]) {
            return false;
        }
    }
    return true;
}

uintptr_t RemoteScanner::FindPattern(const RemoteModuleInfo& moduleInfo, const BYTE* pattern, const char* mask) {
    auto results = FindAllPatterns(moduleInfo, pattern, mask);
    return results.empty() ? 0 : results[0];
}

std::vector<uintptr_t> RemoteScanner::FindAllPatterns(const RemoteModuleInfo& moduleInfo, const BYTE* pattern, const char* mask) {
    std::vector<uintptr_t> results;
    
    size_t patternLength = strlen(mask);
    uintptr_t baseAddress = (uintptr_t)moduleInfo.baseAddress;
    SIZE_T imageSize = moduleInfo.imageSize;
    
    // 分块读取和扫描
    const SIZE_T CHUNK_SIZE = 1024 * 1024; // 1MB chunks
    scanBuffer.resize(CHUNK_SIZE + patternLength);
    
    for (SIZE_T offset = 0; offset < imageSize; offset += CHUNK_SIZE) {
        SIZE_T readSize = min(CHUNK_SIZE + patternLength, imageSize - offset);
        SIZE_T bytesRead = 0;
        
        // 使用间接系统调用读取内存
        NTSTATUS status = IndirectSyscalls::NtReadVirtualMemory(
            this->hProcess,
            (PVOID)(baseAddress + offset),
            scanBuffer.data(),
            readSize,
            &bytesRead
        );
        
        if (status != STATUS_SUCCESS || bytesRead == 0) {
            continue;
        }
        
        // 在本地缓冲区中搜索特征码
        for (SIZE_T i = 0; i < bytesRead - patternLength; i++) {
            if (MatchPattern(&scanBuffer[i], pattern, mask, patternLength)) {
                results.push_back(baseAddress + offset + i);
            }
        }
    }
    
    return results;
}

bool RemoteScanner::ReadRemoteMemory(uintptr_t address, void* buffer, SIZE_T size) {
    SIZE_T bytesRead = 0;
    NTSTATUS status = IndirectSyscalls::NtReadVirtualMemory(
        this->hProcess,
        (PVOID)address,
        buffer,
        size,
        &bytesRead
    );
    
    return (status == STATUS_SUCCESS && bytesRead == size);
}

std::string RemoteScanner::GetWeChatVersion() {
    std::string weixinDllName = ObfuscatedStrings::GetWeixinDllName();
    
    RemoteModuleInfo moduleInfo;
    if (!GetRemoteModuleInfo(weixinDllName, moduleInfo)) {
        return "";
    }
    
    // 读取模块路径
    WCHAR modulePath[MAX_PATH];
    if (GetModuleFileNameExW(this->hProcess, moduleInfo.baseAddress, modulePath, MAX_PATH) == 0) {
        return "";
    }
    
    // 获取文件版本信息
    DWORD handle = 0;
    DWORD versionSize = GetFileVersionInfoSizeW(modulePath, &handle);
    if (versionSize == 0) {
        return "";
    }
    
    std::vector<BYTE> versionData(versionSize);
    if (!GetFileVersionInfoW(modulePath, handle, versionSize, versionData.data())) {
        return "";
    }
    
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

