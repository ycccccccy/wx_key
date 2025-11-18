# wx_key.dll 调用扩展说明

本文档说明 `wx_key/wx_key.dll`（发布包位于 `assets/dll/wx_key.dll`）在项目中的作用、导出接口以及如何在自定义程序中复用它来获取微信数据库/图片密钥。原生项目源码位于 `wx_key/` 目录，导出函数声明见 `wx_key/include/hook_controller.h`。

## 1. DLL 所做的事情

- DLL 由 Flutter 进程加载，随后通过 `RemoteScanner`/`RemoteHooker` 在微信进程中寻找 `Weixin.dll` 内的密钥函数（4.x 不同版本使用特征码匹配）。
- 找到目标地址后，DLL 在远程进程中写入 `Shellcode`，在函数被调用时拦截密钥缓冲区，将 32 字节密钥复制到共享内存，再把状态写入环形队列。
- Flutter 侧（`lib/services/remote_hook_controller.dart`）仅做轮询：每 100ms 调用 `PollKeyData`/`GetStatusMessage`，读取数据并刷新 UI。
- 因为整个 Hook 生命周期、IPC 以及清理逻辑都封装在 DLL 内，其他语言只要按顺序调用导出函数即可复用。

> ⚠️ 现有 Shellcode 是 x64 版本，要求调用进程与微信客户端均为 64 位，并且需要具备打开微信进程的权限（建议以管理员权限运行）。

## 2. 导出函数总览

| 函数 | 声明 | 作用 |
| --- | --- | --- |
| `bool InitializeHook(DWORD targetPid)` | 输入微信 PID | 初始化系统调用、远程扫描 `Weixin.dll`、分配共享缓冲区并安装 Hook。成功后会启动 IPC 监听线程。 |
| `bool PollKeyData(char* keyBuffer, int bufferSize)` | `keyBuffer` 至少 65 字节 | **非阻塞**地检查是否有新密钥。如果有，则写入 64 位十六进制字符串（32 字节密钥）并返回 `true`。一次返回后缓冲区即被清空。 |
| `bool GetStatusMessage(char* statusBuffer, int bufferSize, int* outLevel)` | 建议 `statusBuffer >= 256` | 读取 DLL 内部的状态/日志，`outLevel`：`0=info / 1=success / 2=error`。无消息时返回 `false`。 |
| `bool CleanupHook()` | 无参数 | 卸载远程 Hook、释放共享内存、关闭进程句柄并停止监听线程。 |
| `const char* GetLastErrorMsg()` | 无参数 | 返回最近一次失败的中文/英文错误描述。 |

更多细节可直接参考 `wx_key/include/hook_controller.h` 以及实现文件 `wx_key/src/hook_controller.cpp`。

## 3. 标准调用流程

1. **确认 WeChat 进程**：自行查找 PID（App 内置实现可参考 `DllInjector.findProcessIds`）。
2. **加载 DLL**：调用语言负责把 `wx_key.dll` 加载进当前进程，例如：
   - Dart/Flutter：`DynamicLibrary.open('assets/dll/wx_key.dll')`
   - C#：`var dll = NativeLibrary.Load("wx_key.dll");`
3. **调用 `InitializeHook(pid)`**：
   - 返回 `true` 表示 Hook 安装成功且 IPC 已启动。
   - 若返回 `false`，请用 `GetLastErrorMsg()` 查看原因（可能是不支持的微信版本、没有权限或远程内存分配失败）。
4. **轮询密钥与状态**：
  ```c
  char keyBuf[65] = {0};
  if (PollKeyData(keyBuf, sizeof(keyBuf))) {
      // keyBuf 形如 "9d5d7659a7..."
  }

  int level = 0;
  char statusBuf[256] = {0};
  while (GetStatusMessage(statusBuf, sizeof(statusBuf), &level)) {
      // level: 0/1/2，对应 info/success/error
  }
  ```
   建议使用定时器或后台线程不断轮询（UI 线程应保持非阻塞）。Flutter 版本的实现位于 `RemoteHookController._startPolling()` 供参考。
5. **结束时调用 `CleanupHook()`**：确保远程 Shellcode 被卸载、共享内存和句柄被释放。再次启动前需要重新调用 `InitializeHook`。

## 4. 自定义程序集成示例

以下示例展示如何在 C# 中使用 P/Invoke（其他语言原理一致）：

```csharp
[DllImport("wx_key.dll", CallingConvention = CallingConvention.Cdecl)]
static extern bool InitializeHook(uint targetPid);

[DllImport("wx_key.dll", CallingConvention = CallingConvention.Cdecl)]
static extern bool PollKeyData(StringBuilder keyBuffer, int bufferSize);

[DllImport("wx_key.dll", CallingConvention = CallingConvention.Cdecl)]
static extern bool GetStatusMessage(StringBuilder statusBuffer, int bufferSize, out int level);

[DllImport("wx_key.dll", CallingConvention = CallingConvention.Cdecl)]
static extern bool CleanupHook();

static void Demo(uint pid) {
    if (!InitializeHook(pid)) throw new InvalidOperationException(Marshal.PtrToStringUTF8(GetLastErrorMsg()));

    Task.Run(async () => {
        var keyBuf = new StringBuilder(65);
        var statusBuf = new StringBuilder(256);
        while (true) {
            if (PollKeyData(keyBuf, keyBuf.Capacity)) {
                Console.WriteLine($"Key: {keyBuf}");
            }
            while (GetStatusMessage(statusBuf, statusBuf.Capacity, out var level)) {
                Console.WriteLine($"[DLL:{level}] {statusBuf}");
            }
            await Task.Delay(100);
        }
    });
}
```

Flutter 中的实现请查看 `lib/services/remote_hook_controller.dart`，该文件展示了如何通过 `ffi` 绑定函数指针、如何轮询以及如何把密钥传回状态管理。

## 5. 常见注意事项

- **版本支持**：`RemoteScanner` 内置两套特征码，目前覆盖 4.x 所有可用版本。遇到新版微信无法使用时，请更新 `VersionConfigManager` 中的特征码并重新编译 DLL。
- **运行权限**：需要 `PROCESS_ALL_ACCESS` 打开微信进程，若 `InitializeHook` 返回权限相关错误，请以管理员方式运行。
- **缓冲区大小**：
  - `PollKeyData` 的 `keyBuffer` 至少 `65` 字节（64 个 hex 字符 + `\0`）。
  - `GetStatusMessage` 建议 256+ 字节，否则长日志会被截断。
- **生命周期**：同一进程仅允许一次成功的 `InitializeHook`。如需重新安装，需要先调用 `CleanupHook`。
- **线程模型**：所有导出函数都是同步、线程安全的。轮询时可在独立线程调用；不要在回调中耗时过久，以免阻塞其他轮询。

满足上述要求后，第三方程序便可以像项目内一样，通过 `wx_key.dll` 获取微信数据库/图片密钥，无需重新实现远程注入与 Hook 逻辑。
