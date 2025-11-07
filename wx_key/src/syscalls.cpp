#include "../include/syscalls.h"
#include "../include/string_obfuscator.h"
#include <string>

// 静态成员初始化
bool IndirectSyscalls::initialized = false;
pNtOpenProcess IndirectSyscalls::fnNtOpenProcess = nullptr;
pNtReadVirtualMemory IndirectSyscalls::fnNtReadVirtualMemory = nullptr;
pNtWriteVirtualMemory IndirectSyscalls::fnNtWriteVirtualMemory = nullptr;
pNtAllocateVirtualMemory IndirectSyscalls::fnNtAllocateVirtualMemory = nullptr;
pNtFreeVirtualMemory IndirectSyscalls::fnNtFreeVirtualMemory = nullptr;
pNtProtectVirtualMemory IndirectSyscalls::fnNtProtectVirtualMemory = nullptr;
pNtQueryInformationProcess IndirectSyscalls::fnNtQueryInformationProcess = nullptr;

template<typename T>
bool IndirectSyscalls::ResolveFunction(const char* functionName, T& functionPointer) {
    std::string ntdllName = ObfuscatedStrings::GetNtdllName();
    HMODULE hNtdll = GetModuleHandleA(ntdllName.c_str());
    if (!hNtdll) {
        return false;
    }
    
    functionPointer = reinterpret_cast<T>(GetProcAddress(hNtdll, functionName));
    return (functionPointer != nullptr);
}

bool IndirectSyscalls::Initialize() {
    if (initialized) {
        return true;
    }
    
    bool success = true;
    success &= ResolveFunction("NtOpenProcess", fnNtOpenProcess);
    success &= ResolveFunction("NtReadVirtualMemory", fnNtReadVirtualMemory);
    success &= ResolveFunction("NtWriteVirtualMemory", fnNtWriteVirtualMemory);
    success &= ResolveFunction("NtAllocateVirtualMemory", fnNtAllocateVirtualMemory);
    success &= ResolveFunction("NtFreeVirtualMemory", fnNtFreeVirtualMemory);
    success &= ResolveFunction("NtProtectVirtualMemory", fnNtProtectVirtualMemory);
    success &= ResolveFunction("NtQueryInformationProcess", fnNtQueryInformationProcess);
    
    initialized = success;
    return success;
}

void IndirectSyscalls::Cleanup() {
    // 清理资源
    initialized = false;
}

NTSTATUS IndirectSyscalls::NtOpenProcess(
    PHANDLE ProcessHandle,
    ACCESS_MASK DesiredAccess,
    PMY_OBJECT_ATTRIBUTES ObjectAttributes,
    PMY_CLIENT_ID ClientId
) {
    if (!initialized || !fnNtOpenProcess) {
        return STATUS_UNSUCCESSFUL;
    }
    return fnNtOpenProcess(ProcessHandle, DesiredAccess, ObjectAttributes, ClientId);
}

NTSTATUS IndirectSyscalls::NtReadVirtualMemory(
    HANDLE ProcessHandle,
    PVOID BaseAddress,
    PVOID Buffer,
    SIZE_T BufferSize,
    PSIZE_T NumberOfBytesRead
) {
    if (!initialized || !fnNtReadVirtualMemory) {
        return STATUS_UNSUCCESSFUL;
    }
    return fnNtReadVirtualMemory(ProcessHandle, BaseAddress, Buffer, BufferSize, NumberOfBytesRead);
}

NTSTATUS IndirectSyscalls::NtWriteVirtualMemory(
    HANDLE ProcessHandle,
    PVOID BaseAddress,
    PVOID Buffer,
    SIZE_T BufferSize,
    PSIZE_T NumberOfBytesWritten
) {
    if (!initialized || !fnNtWriteVirtualMemory) {
        return STATUS_UNSUCCESSFUL;
    }
    return fnNtWriteVirtualMemory(ProcessHandle, BaseAddress, Buffer, BufferSize, NumberOfBytesWritten);
}

NTSTATUS IndirectSyscalls::NtAllocateVirtualMemory(
    HANDLE ProcessHandle,
    PVOID* BaseAddress,
    ULONG_PTR ZeroBits,
    PSIZE_T RegionSize,
    ULONG AllocationType,
    ULONG Protect
) {
    if (!initialized || !fnNtAllocateVirtualMemory) {
        return STATUS_UNSUCCESSFUL;
    }
    return fnNtAllocateVirtualMemory(ProcessHandle, BaseAddress, ZeroBits, RegionSize, AllocationType, Protect);
}

NTSTATUS IndirectSyscalls::NtFreeVirtualMemory(
    HANDLE ProcessHandle,
    PVOID* BaseAddress,
    PSIZE_T RegionSize,
    ULONG FreeType
) {
    if (!initialized || !fnNtFreeVirtualMemory) {
        return STATUS_UNSUCCESSFUL;
    }
    return fnNtFreeVirtualMemory(ProcessHandle, BaseAddress, RegionSize, FreeType);
}

NTSTATUS IndirectSyscalls::NtProtectVirtualMemory(
    HANDLE ProcessHandle,
    PVOID* BaseAddress,
    PSIZE_T RegionSize,
    ULONG NewProtect,
    PULONG OldProtect
) {
    if (!initialized || !fnNtProtectVirtualMemory) {
        return STATUS_UNSUCCESSFUL;
    }
    return fnNtProtectVirtualMemory(ProcessHandle, BaseAddress, RegionSize, NewProtect, OldProtect);
}

NTSTATUS IndirectSyscalls::NtQueryInformationProcess(
    HANDLE ProcessHandle,
    PROCESSINFOCLASS ProcessInformationClass,
    PVOID ProcessInformation,
    ULONG ProcessInformationLength,
    PULONG ReturnLength
) {
    if (!initialized || !fnNtQueryInformationProcess) {
        return STATUS_UNSUCCESSFUL;
    }
    return fnNtQueryInformationProcess(ProcessHandle, ProcessInformationClass, ProcessInformation, ProcessInformationLength, ReturnLength);
}

