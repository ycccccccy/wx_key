#include <Windows.h>
#include <string>
#include <sstream>
#include <iomanip>
#include <iostream>
#include <fstream>
#include <Psapi.h>
#include <vector>

#pragma comment(lib, "Psapi.lib")

#pragma region Globals and Core Functions
static std::string g_logFilePath;

// --- 用处说明 ---
// 这也是一个dll代码，它的作用是在你已经通过ida确认某个版本的函数偏移后用它可以自动生成特征码
// 一般情况下只有大版本变动才需要走一次这个流程，比如4.1.2变到4.1.4（函数内部结构变了）
// 小版本变动不需要走这个流程，比如4.1.4.11变到4.1.4.12（函数内部结构没变）
// 然后你就可以在dllmain.cpp中使用这个特征码来注入dll

// --- 日志模块 ---
std::string GetLogFilePath() {
    char tempPath[MAX_PATH];
    GetTempPathA(MAX_PATH, tempPath);
    return std::string(tempPath) + "wx_key_SAFE_SIGNATURE_FINDER.log";
}

void WriteLogToFile(const std::string& message) {
    try {
        std::ofstream logFile;
        logFile.open(g_logFilePath, std::ios::app);
        if (logFile.is_open()) {
            logFile << message << std::endl;
        }
    }
    catch (...) {}
}

// 内存读取函数 
// 使用SEH来防止因访问无效内存而导致的崩溃
bool SafeReadMemory(const void* src, void* dest, size_t size) {
    __try {
        memcpy(dest, src, size);
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}


// --- 扫描函数 ---
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
#pragma endregion Globals and Core Functions


// 特征码生成函数 
bool GenerateSafeSignatureFromAddress(uintptr_t address, size_t length, std::string& pattern, std::string& mask) {
    pattern.clear();
    mask.clear();

    std::vector<unsigned char> memory_buffer(length);
    if (!SafeReadMemory((const void*)address, memory_buffer.data(), length)) {
        return false; // 预读取失败，说明该区域不稳定，直接放弃
    }

    for (size_t i = 0; i < length; ) {
        unsigned char current_byte = memory_buffer[i];

        // --- 掩码规则 ---
        if (current_byte == 0xE8 || current_byte == 0xE9) {
            pattern += current_byte; pattern.append(4, '\x00');
            mask += "x????"; i += 5;
        }
        else if (current_byte >= 0x70 && current_byte <= 0x7F) {
            pattern += current_byte; pattern += '\x00';
            mask += "x?"; i += 2;
        }
        else if (current_byte == 0x0F && i + 1 < length && (memory_buffer[i + 1] >= 0x80 && memory_buffer[i + 1] <= 0x8F)) {
            pattern += current_byte; pattern += memory_buffer[i + 1]; pattern.append(4, '\x00');
            mask += "xx????"; i += 6;
        }
        else {
            pattern += current_byte; mask += "x"; i += 1;
        }
    }
    return true;
}


// --- DLL 主线程  ---
DWORD WINAPI MainThread(HMODULE hModule)
{
    g_logFilePath = GetLogFilePath();
    std::ofstream ofs(g_logFilePath, std::ofstream::out | std::ofstream::trunc);
    ofs.close();

    WriteLogToFile("========== 特征码发现与验证 ==========");

    const uintptr_t KNOWN_GOOD_RVA = 0x5AAB2D0;
    HMODULE hWeixin = GetModuleHandleA("Weixin.dll");
    if (!hWeixin) {
        WriteLogToFile("ERROR: 无法获取 Weixin.dll 模块句柄!");
        return 1;
    }
    uintptr_t baseAddress = (uintptr_t)hWeixin;
    uintptr_t targetFunctionAddress = baseAddress + KNOWN_GOOD_RVA;

    std::stringstream ss;
    ss << "INFO: Weixin.dll 基地址: 0x" << std::hex << baseAddress << std::endl;
    ss << "INFO: 目标函数绝对地址: 0x" << std::hex << targetFunctionAddress;
    WriteLogToFile(ss.str());

    WriteLogToFile("\nINFO: 开始自动搜索并验证唯一特征码..");

    const size_t SIGNATURE_LENGTH = 24;
    const size_t MAX_OFFSET = 0x100;

    for (size_t offset = 0; offset < MAX_OFFSET; ++offset) {
        uintptr_t candidate_start_addr = targetFunctionAddress + offset;

        std::string pattern_str;
        std::string mask_str;

        if (!GenerateSafeSignatureFromAddress(candidate_start_addr, SIGNATURE_LENGTH, pattern_str, mask_str)) {
            ss.str("");
            ss << "\n--- [已跳过] 偏移量: +0x" << std::hex << offset << " (内存不可读) ---";
            WriteLogToFile(ss.str());
            continue;
        }

        ss.str("");
        ss << "\n--- [正在测试] 偏移量: +0x" << std::hex << offset << " ---";
        WriteLogToFile(ss.str());

        std::vector<uintptr_t> results = FindAllPatterns("Weixin.dll", pattern_str.c_str(), mask_str.c_str());

        if (results.size() == 1 && results[0] == candidate_start_addr) {
            WriteLogToFile(">>> SUCCESS! 发现一个稳定且唯一的特征码! <<<");

            ss.str("");
            ss << "  - 函数RVA: 0x" << std::hex << KNOWN_GOOD_RVA << std::endl;
            ss << "  - 偏移量:  +0x" << std::hex << offset << std::endl;
            ss << "  - 最终Pattern (C++格式): " << std::endl << "    const char* pattern = \"";
            for (char c : pattern_str) { ss << "\\x" << std::hex << std::setw(2) << std::setfill('0') << (int)(unsigned char)c; }
            ss << "\";" << std::endl;
            ss << "  - 最终Mask (C++格式): " << std::endl << "    const char* mask = \"" << mask_str << "\";";
            WriteLogToFile(ss.str());

            MessageBoxA(NULL, "成功找到唯一特征码！\n\n详情请查看日志文件。", "成功", MB_OK | MB_ICONINFORMATION);
            return 0;
        }
        else {
            ss.str("");
            ss << "STATUS: FAILED. 找到 " << results.size() << " 个匹配项。";
            WriteLogToFile(ss.str());
        }
    }

    WriteLogToFile("\n\nERROR: 在指定范围内未能找到任何唯一有效的特征码。");
    MessageBoxA(NULL, "搜索完成，但未能找到唯一特征码。\n\n请检查RVA或扩大搜索范围。", "失败", MB_OK | MB_ICONWARNING);
    return 0;
}


// --- DLL 入口点 ---
BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID lpReserved)
{
    if (ul_reason_for_call == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(hModule);
        HANDLE hThread = CreateThread(nullptr, 0, (LPTHREAD_START_ROUTINE)MainThread, hModule, 0, nullptr);
        if (hThread) {
            CloseHandle(hThread);
        }
    }
    return TRUE;
}