// 远程Hook控制器DLL入口点
// 这个DLL在Flutter进程中运行，不会被注入到目标进程
#include <Windows.h>
#define HOOK_EXPORTS

#include "include/hook_controller.h"

#pragma comment(lib, "Psapi.lib")
#pragma comment(lib, "version.lib")

// DLL 入口函数
BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID lpReserved) {
    switch (ul_reason_for_call) {
    case DLL_PROCESS_ATTACH:
        DisableThreadLibraryCalls(hModule); 
        break;
        
    case DLL_PROCESS_DETACH:
        // 清理资源
        CleanupHook();
        break;
    }
    return TRUE;
}