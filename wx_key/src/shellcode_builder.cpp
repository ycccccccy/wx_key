#include "../include/shellcode_builder.h"

ShellcodeBuilder::ShellcodeBuilder() {
    shellcode.reserve(512); // 预分配空间
}

ShellcodeBuilder::~ShellcodeBuilder() {
}

void ShellcodeBuilder::Clear() {
    shellcode.clear();
}

size_t ShellcodeBuilder::GetShellcodeSize() const {
    return shellcode.size();
}

// ========== 基础字节发射 ==========
void ShellcodeBuilder::EmitByte(BYTE value) {
    shellcode.push_back(value);
}

void ShellcodeBuilder::EmitWord(WORD value) {
    shellcode.push_back((BYTE)(value & 0xFF));
    shellcode.push_back((BYTE)((value >> 8) & 0xFF));
}

void ShellcodeBuilder::EmitDword(DWORD value) {
    shellcode.push_back((BYTE)(value & 0xFF));
    shellcode.push_back((BYTE)((value >> 8) & 0xFF));
    shellcode.push_back((BYTE)((value >> 16) & 0xFF));
    shellcode.push_back((BYTE)((value >> 24) & 0xFF));
}

void ShellcodeBuilder::EmitQword(UINT64 value) {
    for (int i = 0; i < 8; i++) {
        shellcode.push_back((BYTE)((value >> (i * 8)) & 0xFF));
    }
}

// ========== PUSH指令 ==========
void ShellcodeBuilder::EmitPushRax() { EmitByte(0x50); }
void ShellcodeBuilder::EmitPushRcx() { EmitByte(0x51); }
void ShellcodeBuilder::EmitPushRdx() { EmitByte(0x52); }
void ShellcodeBuilder::EmitPushRbx() { EmitByte(0x53); }
void ShellcodeBuilder::EmitPushRbp() { EmitByte(0x55); }
void ShellcodeBuilder::EmitPushRsi() { EmitByte(0x56); }
void ShellcodeBuilder::EmitPushRdi() { EmitByte(0x57); }

void ShellcodeBuilder::EmitPushR8()  { EmitByte(0x41); EmitByte(0x50); }
void ShellcodeBuilder::EmitPushR9()  { EmitByte(0x41); EmitByte(0x51); }
void ShellcodeBuilder::EmitPushR10() { EmitByte(0x41); EmitByte(0x52); }
void ShellcodeBuilder::EmitPushR11() { EmitByte(0x41); EmitByte(0x53); }
void ShellcodeBuilder::EmitPushR12() { EmitByte(0x41); EmitByte(0x54); }
void ShellcodeBuilder::EmitPushR13() { EmitByte(0x41); EmitByte(0x55); }
void ShellcodeBuilder::EmitPushR14() { EmitByte(0x41); EmitByte(0x56); }
void ShellcodeBuilder::EmitPushR15() { EmitByte(0x41); EmitByte(0x57); }

void ShellcodeBuilder::EmitPushfq() { EmitByte(0x9C); }

// ========== POP指令 ==========
void ShellcodeBuilder::EmitPopRax() { EmitByte(0x58); }
void ShellcodeBuilder::EmitPopRcx() { EmitByte(0x59); }
void ShellcodeBuilder::EmitPopRdx() { EmitByte(0x5A); }
void ShellcodeBuilder::EmitPopRbx() { EmitByte(0x5B); }
void ShellcodeBuilder::EmitPopRbp() { EmitByte(0x5D); }
void ShellcodeBuilder::EmitPopRsi() { EmitByte(0x5E); }
void ShellcodeBuilder::EmitPopRdi() { EmitByte(0x5F); }

void ShellcodeBuilder::EmitPopR8()  { EmitByte(0x41); EmitByte(0x58); }
void ShellcodeBuilder::EmitPopR9()  { EmitByte(0x41); EmitByte(0x59); }
void ShellcodeBuilder::EmitPopR10() { EmitByte(0x41); EmitByte(0x5A); }
void ShellcodeBuilder::EmitPopR11() { EmitByte(0x41); EmitByte(0x5B); }
void ShellcodeBuilder::EmitPopR12() { EmitByte(0x41); EmitByte(0x5C); }
void ShellcodeBuilder::EmitPopR13() { EmitByte(0x41); EmitByte(0x5D); }
void ShellcodeBuilder::EmitPopR14() { EmitByte(0x41); EmitByte(0x5E); }
void ShellcodeBuilder::EmitPopR15() { EmitByte(0x41); EmitByte(0x5F); }

void ShellcodeBuilder::EmitPopfq() { EmitByte(0x9D); }

// ========== MOV指令 ==========
void ShellcodeBuilder::EmitMovRaxImm64(UINT64 value) {
    // mov rax, imm64
    EmitByte(0x48);
    EmitByte(0xB8);
    EmitQword(value);
}

void ShellcodeBuilder::EmitMovRcxImm64(UINT64 value) {
    // mov rcx, imm64
    EmitByte(0x48);
    EmitByte(0xB9);
    EmitQword(value);
}

void ShellcodeBuilder::EmitMovRdxImm64(UINT64 value) {
    // mov rdx, imm64
    EmitByte(0x48);
    EmitByte(0xBA);
    EmitQword(value);
}

// ========== 控制流指令 ==========
void ShellcodeBuilder::EmitCallRax() {
    // call rax
    EmitByte(0xFF);
    EmitByte(0xD0);
}

void ShellcodeBuilder::EmitJmpRax() {
    // jmp rax
    EmitByte(0xFF);
    EmitByte(0xE0);
}

void ShellcodeBuilder::EmitRet() {
    // ret
    EmitByte(0xC3);
}

// ========== 内存操作 ==========
void ShellcodeBuilder::EmitMovMemRax(uintptr_t memAddress) {
    // mov [memAddress], rax
    EmitMovRcxImm64(memAddress);
    EmitByte(0x48);
    EmitByte(0x89);
    EmitByte(0x01); // mov [rcx], rax
}

void ShellcodeBuilder::EmitMovMemRdx(uintptr_t memAddress) {
    // mov [memAddress], rdx
    EmitMovRcxImm64(memAddress);
    EmitByte(0x48);
    EmitByte(0x89);
    EmitByte(0x11); // mov [rcx], rdx
}

// ========== 构建完整的Hook Shellcode ==========
std::vector<BYTE> ShellcodeBuilder::BuildHookShellcode(const ShellcodeConfig& config) {
    Clear();
    
    // ===== 1. 保存所有寄存器 =====
    EmitPushfq();
    EmitPushRax();
    EmitPushRcx();
    EmitPushRdx();
    EmitPushRbx();
    EmitPushRbp();
    EmitPushRsi();
    EmitPushRdi();
    EmitPushR8();
    EmitPushR9();
    EmitPushR10();
    EmitPushR11();
    EmitPushR12();
    EmitPushR13();
    EmitPushR14();
    EmitPushR15();
    
    // ===== 2. 提取密钥数据 =====
    // RDX寄存器指向密钥结构体
    // 结构体偏移：+0x08 = pKeyBuffer, +0x10 = keySize
    
    // 读取keySize到RAX
    // mov rax, [rdx + 0x10]
    EmitByte(0x48);
    EmitByte(0x8B);
    EmitByte(0x42);
    EmitByte(0x10);
    
    // 检查keySize是否为32
    // cmp rax, 32
    EmitByte(0x48);
    EmitByte(0x83);
    EmitByte(0xF8);
    EmitByte(0x20);
    
    // jne skip_copy (如果不是32，跳过复制)
    // 先写入占位字节，稍后计算实际偏移后回填
    EmitByte(0x75); // JNE rel8
    size_t skipOffsetPos = shellcode.size(); // 记录需要回填的位置
    EmitByte(0x00); // 临时占位，将在第250-253行回填实际偏移值
    
    // 读取pKeyBuffer到RCX
    // mov rcx, [rdx + 0x08]
    EmitByte(0x48);
    EmitByte(0x8B);
    EmitByte(0x4A);
    EmitByte(0x08);
    
    // ===== 3. 复制密钥到共享内存 =====
    // 加载共享内存地址到RDI
    EmitMovRdxImm64((UINT64)config.sharedMemoryAddress);
    EmitByte(0x48);
    EmitByte(0x89);
    EmitByte(0xD7); // mov rdi, rdx
    
    // 写入dataSize (32)
    // mov dword ptr [rdi], 32
    EmitByte(0xC7);
    EmitByte(0x07);
    EmitDword(32);
    
    // 复制32字节密钥数据
    // RCX = source (pKeyBuffer)
    // RDI + 4 = destination (共享内存的keyBuffer字段)
    EmitByte(0x48);
    EmitByte(0x83);
    EmitByte(0xC7);
    EmitByte(0x04); // add rdi, 4
    
    // 使用movs指令复制32字节
    EmitByte(0x48);
    EmitByte(0x89);
    EmitByte(0xCE); // mov rsi, rcx
    
    // mov rcx, 32
    EmitMovRcxImm64(32);
    
    // rep movsb
    EmitByte(0xF3);
    EmitByte(0xA4);
    
    // ===== 4. 写入timestamp标记 =====
    // 恢复RDI到缓冲区起始位置（减去36：4字节dataSize + 32字节keyBuffer）
    EmitByte(0x48);
    EmitByte(0x83);
    EmitByte(0xEF);
    EmitByte(0x24); // sub rdi, 36
    
    // 获取当前时间戳（使用GetTickCount）
    HMODULE hKernel32 = GetModuleHandleA("kernel32.dll");
    PVOID pGetTickCount = GetProcAddress(hKernel32, "GetTickCount");
    
    EmitMovRaxImm64((UINT64)pGetTickCount);
    
    // 预留栈空间（x64调用约定要求shadow space）
    // sub rsp, 32
    EmitByte(0x48);
    EmitByte(0x83);
    EmitByte(0xEC);
    EmitByte(0x20);
    
    EmitCallRax();
    
    // 恢复栈
    // add rsp, 32
    EmitByte(0x48);
    EmitByte(0x83);
    EmitByte(0xC4);
    EmitByte(0x20);
    
    // 写入timestamp到缓冲区（offset +36）
    // mov [rdi + 36], eax
    EmitByte(0x89);
    EmitByte(0x47);
    EmitByte(0x24); // 0x24 = 36
    
    // 写入processId到缓冲区（offset +40）
    // 获取当前进程ID（使用GetCurrentProcessId）
    PVOID pGetCurrentProcessId = GetProcAddress(hKernel32, "GetCurrentProcessId");
    EmitMovRaxImm64((UINT64)pGetCurrentProcessId);
    
    // 预留栈空间
    // sub rsp, 32
    EmitByte(0x48);
    EmitByte(0x83);
    EmitByte(0xEC);
    EmitByte(0x20);
    
    EmitCallRax();
    
    // 恢复栈
    // add rsp, 32
    EmitByte(0x48);
    EmitByte(0x83);
    EmitByte(0xC4);
    EmitByte(0x20);
    
    // 写入processId
    // mov [rdi + 40], eax
    EmitByte(0x89);
    EmitByte(0x47);
    EmitByte(0x28); // 0x28 = 40
    
    // skip_copy标签位置 - 回填前向引用的跳转偏移
    size_t currentPos = shellcode.size();
    size_t offset = currentPos - skipOffsetPos - 1;
    
    // 验证偏移值在rel8范围内（-128到+127）
    if (offset > 127) {
        // 如果偏移超出范围，说明shellcode逻辑有问题
        // 正常情况下，skip_copy跳转距离不会超过127字节
        offset = 127; // 保护性措施，避免截断错误
    }
    
    // 回填实际的跳转偏移值
    shellcode[skipOffsetPos] = static_cast<BYTE>(offset & 0xFF);
    
    // ===== 5. 恢复所有寄存器 =====
    EmitPopR15();
    EmitPopR14();
    EmitPopR13();
    EmitPopR12();
    EmitPopR11();
    EmitPopR10();
    EmitPopR9();
    EmitPopR8();
    EmitPopRdi();
    EmitPopRsi();
    EmitPopRbp();
    EmitPopRbx();
    EmitPopRdx();
    EmitPopRcx();
    EmitPopRax();
    EmitPopfq();
    
    // ===== 6. 跳转到Trampoline继续执行原始函数 =====
    EmitMovRaxImm64(config.trampolineAddress);
    EmitJmpRax();
    
    return shellcode;
}

