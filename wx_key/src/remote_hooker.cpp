#include "../include/remote_hooker.h"
#include "../include/syscalls.h"
#include "../include/shellcode_builder.h"
#include <algorithm>

// 简单的x64反汇编长度检测器
// 支持常见指令，用于计算需要备份多少字节
namespace X64Disasm {
    // 检查是否为REX前缀 (0x40-0x4F)
    inline bool IsRexPrefix(BYTE b) {
        return (b >= 0x40 && b <= 0x4F);
    }
    
    // 获取单条指令的长度
    size_t GetInstructionLength(const BYTE* code) {
        size_t len = 0;
        bool hasRex = false;
        
        // 跳过REX前缀
        if (IsRexPrefix(code[len])) {
            hasRex = true;
            len++;
        }
        
        BYTE opcode = code[len];
        len++;
        
        // 常见指令长度判断（简化版）
        switch (opcode) {
            // 单字节指令
            case 0x50: case 0x51: case 0x52: case 0x53:
            case 0x54: case 0x55: case 0x56: case 0x57:
            case 0x58: case 0x59: case 0x5A: case 0x5B:
            case 0x5C: case 0x5D: case 0x5E: case 0x5F:
            case 0x90: case 0xC3: case 0xCC:
                return len;
                
            // MOV指令
            case 0x88: case 0x89: case 0x8A: case 0x8B:
                len++; // ModRM
                if ((code[len-1] & 0xC0) != 0xC0) {
                    // 有内存操作数
                    BYTE modrm = code[len-1];
                    BYTE mod = (modrm >> 6) & 3;
                    BYTE rm = modrm & 7;
                    
                    if (rm == 4) len++; // 有SIB字节
                    if (mod == 1) len++; // disp8
                    else if (mod == 2) len += 4; // disp32
                }
                return len;
                
            // 立即数指令
            case 0xB0: case 0xB1: case 0xB2: case 0xB3:
            case 0xB4: case 0xB5: case 0xB6: case 0xB7:
                return len + 1; // imm8
                
            case 0xB8: case 0xB9: case 0xBA: case 0xBB:
            case 0xBC: case 0xBD: case 0xBE: case 0xBF:
                return len + (hasRex ? 8 : 4); // imm32/64
                
            // 短跳转
            case 0x70: case 0x71: case 0x72: case 0x73:
            case 0x74: case 0x75: case 0x76: case 0x77:
            case 0x78: case 0x79: case 0x7A: case 0x7B:
            case 0x7C: case 0x7D: case 0x7E: case 0x7F:
            case 0xEB:
                return len + 1; // rel8
                
            case 0xE8: case 0xE9: // CALL/JMP rel32
                return len + 4;
                
            // 双字节指令
            case 0x0F:
                len++;
                opcode = code[len-1];
                if (opcode >= 0x80 && opcode <= 0x8F) {
                    return len + 4; // 条件跳转 rel32
                }
                return len + 1; // 简化处理
                
            // LEA
            case 0x8D:
                len++; // ModRM
                if ((code[len-1] & 0x07) == 4) len++; // SIB
                if (((code[len-1] >> 6) & 3) == 2) len += 4; // disp32
                return len;
                
            default:
                // 未知指令，返回最小长度
                return len + 1;
        }
    }
}

RemoteHooker::RemoteHooker(HANDLE hProcess)
    : hProcess(hProcess)
    , targetAddress(0)
    , remoteShellcodeAddress(0)
    , trampolineAddress(0)
    , isHookInstalled(false)
{
}

RemoteHooker::~RemoteHooker() {
    UninstallHook();
}

PVOID RemoteHooker::RemoteAllocate(SIZE_T size, DWORD protect) {
    PVOID baseAddress = nullptr;
    SIZE_T regionSize = size;
    
    NTSTATUS status = IndirectSyscalls::NtAllocateVirtualMemory(
        hProcess,
        &baseAddress,
        0,
        &regionSize,
        MEM_COMMIT | MEM_RESERVE,
        protect
    );
    
    return (status == STATUS_SUCCESS) ? baseAddress : nullptr;
}

bool RemoteHooker::RemoteFree(PVOID address, SIZE_T size) {
    SIZE_T regionSize = size;
    
    NTSTATUS status = IndirectSyscalls::NtFreeVirtualMemory(
        hProcess,
        &address,
        &regionSize,
        MEM_RELEASE
    );
    
    return (status == STATUS_SUCCESS);
}

bool RemoteHooker::RemoteWrite(PVOID address, const void* data, SIZE_T size) {
    SIZE_T bytesWritten = 0;
    
    NTSTATUS status = IndirectSyscalls::NtWriteVirtualMemory(
        hProcess,
        address,
        (PVOID)data,
        size,
        &bytesWritten
    );
    
    return (status == STATUS_SUCCESS && bytesWritten == size);
}

bool RemoteHooker::RemoteRead(PVOID address, void* buffer, SIZE_T size) {
    SIZE_T bytesRead = 0;
    
    NTSTATUS status = IndirectSyscalls::NtReadVirtualMemory(
        hProcess,
        address,
        buffer,
        size,
        &bytesRead
    );
    
    return (status == STATUS_SUCCESS && bytesRead == size);
}

bool RemoteHooker::RemoteProtect(PVOID address, SIZE_T size, DWORD newProtect, DWORD* oldProtect) {
    ULONG oldProt = 0;
    
    NTSTATUS status = IndirectSyscalls::NtProtectVirtualMemory(
        hProcess,
        &address,
        &size,
        newProtect,
        &oldProt
    );
    
    if (oldProtect) {
        *oldProtect = oldProt;
    }
    
    return (status == STATUS_SUCCESS);
}

size_t RemoteHooker::CalculateHookLength(const BYTE* code) {
    size_t totalLen = 0;
    const size_t minLen = 14; // 我们需要至少14字节来放置长跳转
    
    while (totalLen < minLen) {
        size_t instrLen = X64Disasm::GetInstructionLength(code + totalLen);
        if (instrLen == 0) {
            return 0; // 失败
        }
        totalLen += instrLen;
    }
    
    return totalLen;
}

bool RemoteHooker::CreateTrampoline(uintptr_t targetAddr) {
    // 读取目标地址的原始字节
    BYTE originalCode[32];
    if (!RemoteRead((PVOID)targetAddr, originalCode, sizeof(originalCode))) {
        return false;
    }
    
    // 计算需要备份的指令长度
    size_t hookLen = CalculateHookLength(originalCode);
    if (hookLen == 0 || hookLen > 32) {
        return false;
    }
    
    originalBytes.assign(originalCode, originalCode + hookLen);
    
    // 分配Trampoline内存
    // Trampoline = 原始指令 + 跳转回原函数的JMP指令
    SIZE_T trampolineSize = hookLen + 14; // 原始指令 + 长跳转
    PVOID trampolineAddr = RemoteAllocate(trampolineSize, PAGE_EXECUTE_READWRITE);
    
    if (!trampolineAddr) {
        return false;
    }
    
    trampolineAddress = (uintptr_t)trampolineAddr;
    
    // 写入原始指令
    if (!RemoteWrite(trampolineAddr, originalCode, hookLen)) {
        RemoteFree(trampolineAddr, trampolineSize);
        trampolineAddress = 0;
        return false;
    }
    
    // 生成跳转回原函数的指令
    uintptr_t returnAddress = targetAddr + hookLen;
    std::vector<BYTE> jmpBack = GenerateJumpInstruction(trampolineAddress + hookLen, returnAddress);
    
    if (!RemoteWrite((PVOID)(trampolineAddress + hookLen), jmpBack.data(), jmpBack.size())) {
        RemoteFree(trampolineAddr, trampolineSize);
        trampolineAddress = 0;
        return false;
    }
    
    return true;
}

std::vector<BYTE> RemoteHooker::GenerateJumpInstruction(uintptr_t from, uintptr_t to) {
    std::vector<BYTE> jmp;
    
    // 计算相对偏移
    INT64 offset = (INT64)to - (INT64)from - 5;
    
    // 如果可以使用5字节短跳转（rel32）
    if (offset >= INT32_MIN && offset <= INT32_MAX) {
        jmp.push_back(0xE9); // JMP rel32
        INT32 offset32 = (INT32)offset;
        jmp.push_back((BYTE)(offset32 & 0xFF));
        jmp.push_back((BYTE)((offset32 >> 8) & 0xFF));
        jmp.push_back((BYTE)((offset32 >> 16) & 0xFF));
        jmp.push_back((BYTE)((offset32 >> 24) & 0xFF));
    }
    else {
        // 使用14字节长跳转
        // mov rax, addr64
        jmp.push_back(0x48);
        jmp.push_back(0xB8);
        for (int i = 0; i < 8; i++) {
            jmp.push_back((BYTE)((to >> (i * 8)) & 0xFF));
        }
        // jmp rax
        jmp.push_back(0xFF);
        jmp.push_back(0xE0);
    }
    
    return jmp;
}

bool RemoteHooker::InstallHook(uintptr_t targetFunctionAddress, const ShellcodeConfig& shellcodeConfig) {
    if (isHookInstalled) {
        return false; // 已经安装过Hook
    }
    
    targetAddress = targetFunctionAddress;
    
    // 1. 创建Trampoline
    if (!CreateTrampoline(targetAddress)) {
        return false;
    }
    
    // 2. 构建Shellcode（需要更新配置以包含正确的trampoline地址）
    ShellcodeConfig updatedConfig = shellcodeConfig;
    updatedConfig.trampolineAddress = trampolineAddress;
    
    ShellcodeBuilder builder;
    std::vector<BYTE> shellcode = builder.BuildHookShellcode(updatedConfig);
    
    // 3. 在远程进程中分配Shellcode内存
    PVOID remoteShellcode = RemoteAllocate(shellcode.size(), PAGE_EXECUTE_READWRITE);
    if (!remoteShellcode) {
        // 清理Trampoline
        RemoteFree((PVOID)trampolineAddress, originalBytes.size() + 14);
        trampolineAddress = 0;
        return false;
    }
    
    remoteShellcodeAddress = (uintptr_t)remoteShellcode;
    
    // 4. 写入Shellcode
    if (!RemoteWrite(remoteShellcode, shellcode.data(), shellcode.size())) {
        RemoteFree(remoteShellcode, shellcode.size());
        RemoteFree((PVOID)trampolineAddress, originalBytes.size() + 14);
        remoteShellcodeAddress = 0;
        trampolineAddress = 0;
        return false;
    }
    
    // 5. 生成Hook跳转指令
    std::vector<BYTE> hookJump = GenerateJumpInstruction(targetAddress, remoteShellcodeAddress);
    
    // 确保有足够的空间
    if (hookJump.size() > originalBytes.size()) {
        RemoteFree(remoteShellcode, shellcode.size());
        RemoteFree((PVOID)trampolineAddress, originalBytes.size() + 14);
        remoteShellcodeAddress = 0;
        trampolineAddress = 0;
        return false;
    }
    
    // 填充NOP
    while (hookJump.size() < originalBytes.size()) {
        hookJump.push_back(0x90); // NOP
    }
    
    // 6. 修改目标函数的保护属性
    DWORD oldProtect;
    if (!RemoteProtect((PVOID)targetAddress, originalBytes.size(), PAGE_EXECUTE_READWRITE, &oldProtect)) {
        RemoteFree(remoteShellcode, shellcode.size());
        RemoteFree((PVOID)trampolineAddress, originalBytes.size() + 14);
        remoteShellcodeAddress = 0;
        trampolineAddress = 0;
        return false;
    }
    
    // 7. 写入Hook跳转指令（原子操作）
    bool writeSuccess = RemoteWrite((PVOID)targetAddress, hookJump.data(), hookJump.size());
    
    // 8. 恢复原始保护属性
    DWORD tempProtect;
    RemoteProtect((PVOID)targetAddress, originalBytes.size(), oldProtect, &tempProtect);
    
    if (!writeSuccess) {
        RemoteFree(remoteShellcode, shellcode.size());
        RemoteFree((PVOID)trampolineAddress, originalBytes.size() + 14);
        remoteShellcodeAddress = 0;
        trampolineAddress = 0;
        return false;
    }
    
    isHookInstalled = true;
    return true;
}

bool RemoteHooker::UninstallHook() {
    if (!isHookInstalled) {
        return true;
    }
    
    // 1. 修改保护属性
    DWORD oldProtect;
    if (!RemoteProtect((PVOID)targetAddress, originalBytes.size(), PAGE_EXECUTE_READWRITE, &oldProtect)) {
        return false;
    }
    
    // 2. 恢复原始字节
    bool restoreSuccess = RemoteWrite((PVOID)targetAddress, originalBytes.data(), originalBytes.size());
    
    // 3. 恢复保护属性
    DWORD tempProtect;
    RemoteProtect((PVOID)targetAddress, originalBytes.size(), oldProtect, &tempProtect);
    
    // 4. 释放远程内存
    if (remoteShellcodeAddress) {
        RemoteFree((PVOID)remoteShellcodeAddress, 512); // 估算大小
        remoteShellcodeAddress = 0;
    }
    
    if (trampolineAddress) {
        RemoteFree((PVOID)trampolineAddress, originalBytes.size() + 14);
        trampolineAddress = 0;
    }
    
    isHookInstalled = false;
    return restoreSuccess;
}

