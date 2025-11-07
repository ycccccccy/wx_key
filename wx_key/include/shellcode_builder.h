#ifndef SHELLCODE_BUILDER_H
#define SHELLCODE_BUILDER_H

#include <Windows.h>
#include <vector>
#include <string>

// Shellcode配置
struct ShellcodeConfig {
    PVOID sharedMemoryAddress;  // 共享内存地址
    HANDLE eventHandle;         // 事件句柄
    uintptr_t trampolineAddress; // Trampoline地址（原始函数继续执行的地址）
};

// Shellcode构建器
class ShellcodeBuilder {
public:
    ShellcodeBuilder();
    ~ShellcodeBuilder();
    
    // 构建Hook Shellcode
    std::vector<BYTE> BuildHookShellcode(const ShellcodeConfig& config);
    
    // 获取Shellcode大小
    size_t GetShellcodeSize() const;
    
private:
    std::vector<BYTE> shellcode;
    
    // x64汇编辅助函数
    void EmitPushRax();
    void EmitPushRcx();
    void EmitPushRdx();
    void EmitPushR8();
    void EmitPushR9();
    void EmitPushR10();
    void EmitPushR11();
    void EmitPushRbx();
    void EmitPushRbp();
    void EmitPushRsi();
    void EmitPushRdi();
    void EmitPushR12();
    void EmitPushR13();
    void EmitPushR14();
    void EmitPushR15();
    void EmitPushfq();
    
    void EmitPopR15();
    void EmitPopR14();
    void EmitPopR13();
    void EmitPopR12();
    void EmitPopRdi();
    void EmitPopRsi();
    void EmitPopRbp();
    void EmitPopRbx();
    void EmitPopR11();
    void EmitPopR10();
    void EmitPopR9();
    void EmitPopR8();
    void EmitPopRdx();
    void EmitPopRcx();
    void EmitPopRax();
    void EmitPopfq();
    
    // 通用指令
    void EmitByte(BYTE value);
    void EmitWord(WORD value);
    void EmitDword(DWORD value);
    void EmitQword(UINT64 value);
    
    // 复杂指令
    void EmitMovRaxImm64(UINT64 value);
    void EmitMovRcxImm64(UINT64 value);
    void EmitMovRdxImm64(UINT64 value);
    void EmitCallRax();
    void EmitJmpRax();
    void EmitRet();
    
    // 数据操作
    void EmitMovMemRax(uintptr_t memAddress);
    void EmitMovMemRdx(uintptr_t memAddress);
    
    // 清除Shellcode
    void Clear();
};

#endif // SHELLCODE_BUILDER_H

