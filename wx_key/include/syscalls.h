#ifndef SYSCALLS_H
#define SYSCALLS_H

#include <Windows.h>
#include <winternl.h>

// Extended NT definitions
#ifndef STATUS_SUCCESS
#define STATUS_SUCCESS ((NTSTATUS)0x00000000L)
#endif

#ifndef STATUS_UNSUCCESSFUL
#define STATUS_UNSUCCESSFUL ((NTSTATUS)0xC0000001L)
#endif

// CLIENT_ID structure (if not defined)
#ifndef _CLIENT_ID_DEFINED
#define _CLIENT_ID_DEFINED
typedef struct _MY_CLIENT_ID {
    PVOID UniqueProcess;
    PVOID UniqueThread;
} MY_CLIENT_ID, *PMY_CLIENT_ID;
#endif

// OBJECT_ATTRIBUTES structure (simplified)
#ifndef _MY_OBJECT_ATTRIBUTES_DEFINED
#define _MY_OBJECT_ATTRIBUTES_DEFINED
typedef struct _MY_OBJECT_ATTRIBUTES {
    ULONG Length;
    HANDLE RootDirectory;
    PVOID ObjectName;
    ULONG Attributes;
    PVOID SecurityDescriptor;
    PVOID SecurityQualityOfService;
} MY_OBJECT_ATTRIBUTES, *PMY_OBJECT_ATTRIBUTES;
#endif

// NT函数原型
typedef NTSTATUS(NTAPI* pNtOpenProcess)(
    PHANDLE ProcessHandle,
    ACCESS_MASK DesiredAccess,
    PMY_OBJECT_ATTRIBUTES ObjectAttributes,
    PMY_CLIENT_ID ClientId
);

typedef NTSTATUS(NTAPI* pNtReadVirtualMemory)(
    HANDLE ProcessHandle,
    PVOID BaseAddress,
    PVOID Buffer,
    SIZE_T BufferSize,
    PSIZE_T NumberOfBytesRead
);

typedef NTSTATUS(NTAPI* pNtWriteVirtualMemory)(
    HANDLE ProcessHandle,
    PVOID BaseAddress,
    PVOID Buffer,
    SIZE_T BufferSize,
    PSIZE_T NumberOfBytesWritten
);

typedef NTSTATUS(NTAPI* pNtAllocateVirtualMemory)(
    HANDLE ProcessHandle,
    PVOID* BaseAddress,
    ULONG_PTR ZeroBits,
    PSIZE_T RegionSize,
    ULONG AllocationType,
    ULONG Protect
);

typedef NTSTATUS(NTAPI* pNtFreeVirtualMemory)(
    HANDLE ProcessHandle,
    PVOID* BaseAddress,
    PSIZE_T RegionSize,
    ULONG FreeType
);

typedef NTSTATUS(NTAPI* pNtProtectVirtualMemory)(
    HANDLE ProcessHandle,
    PVOID* BaseAddress,
    PSIZE_T RegionSize,
    ULONG NewProtect,
    PULONG OldProtect
);

typedef NTSTATUS(NTAPI* pNtQueryInformationProcess)(
    HANDLE ProcessHandle,
    PROCESSINFOCLASS ProcessInformationClass,
    PVOID ProcessInformation,
    ULONG ProcessInformationLength,
    PULONG ReturnLength
);

// 间接系统调用类
class IndirectSyscalls {
public:
    static bool Initialize();
    static void Cleanup();
    
    // 封装的系统调用函数
    static NTSTATUS NtOpenProcess(
        PHANDLE ProcessHandle,
        ACCESS_MASK DesiredAccess,
        PMY_OBJECT_ATTRIBUTES ObjectAttributes,
        PMY_CLIENT_ID ClientId
    );
    
    static NTSTATUS NtReadVirtualMemory(
        HANDLE ProcessHandle,
        PVOID BaseAddress,
        PVOID Buffer,
        SIZE_T BufferSize,
        PSIZE_T NumberOfBytesRead
    );
    
    static NTSTATUS NtWriteVirtualMemory(
        HANDLE ProcessHandle,
        PVOID BaseAddress,
        PVOID Buffer,
        SIZE_T BufferSize,
        PSIZE_T NumberOfBytesWritten
    );
    
    static NTSTATUS NtAllocateVirtualMemory(
        HANDLE ProcessHandle,
        PVOID* BaseAddress,
        ULONG_PTR ZeroBits,
        PSIZE_T RegionSize,
        ULONG AllocationType,
        ULONG Protect
    );
    
    static NTSTATUS NtFreeVirtualMemory(
        HANDLE ProcessHandle,
        PVOID* BaseAddress,
        PSIZE_T RegionSize,
        ULONG FreeType
    );
    
    static NTSTATUS NtProtectVirtualMemory(
        HANDLE ProcessHandle,
        PVOID* BaseAddress,
        PSIZE_T RegionSize,
        ULONG NewProtect,
        PULONG OldProtect
    );
    
    static NTSTATUS NtQueryInformationProcess(
        HANDLE ProcessHandle,
        PROCESSINFOCLASS ProcessInformationClass,
        PVOID ProcessInformation,
        ULONG ProcessInformationLength,
        PULONG ReturnLength
    );

private:
    static bool initialized;
    
    // 动态获取的函数指针
    static pNtOpenProcess fnNtOpenProcess;
    static pNtReadVirtualMemory fnNtReadVirtualMemory;
    static pNtWriteVirtualMemory fnNtWriteVirtualMemory;
    static pNtAllocateVirtualMemory fnNtAllocateVirtualMemory;
    static pNtFreeVirtualMemory fnNtFreeVirtualMemory;
    static pNtProtectVirtualMemory fnNtProtectVirtualMemory;
    static pNtQueryInformationProcess fnNtQueryInformationProcess;
    
    // 辅助函数：从ntdll解析函数地址
    template<typename T>
    static bool ResolveFunction(const char* functionName, T& functionPointer);
};

#endif // SYSCALLS_H

