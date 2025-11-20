# wx_key.dll 集成开发指南

本文档旨在帮助开发者快速理解并集成 `wx_key.dll`。该组件封装了微信逆向工程的核心逻辑，让你无需关心底层的内存扫描与 Hook 实现，即可在 C#、Flutter 或 C++ 等上层应用中获取微信数据库密钥与图片密钥。

---

## 1. 核心原理

简单来说，`wx_key.dll` 充当了**宿主程序**与**微信进程**之间的桥梁。

1.  **注入与扫描**：当你的程序加载此 DLL 并调用初始化后，它会通过 `RemoteScanner` 扫描微信进程内存，利用特征码定位密钥获取函数的入口（支持 4.x 多个版本）。
2.  **拦截与共享**：定位成功后，DLL 会写入一段 Shellcode 进行 Hook。当微信尝试读取数据库时，Shellcode 会拦截 32 字节的密钥，将其拷贝到**共享内存环形队列**中。
3.  **轮询机制**：由于 Hook 运行在微信进程内，为了稳定传输，我们采用了“非阻塞轮询”方案。你的程序只需定时检查共享内存，即可拿到密钥。

> **⚠️ 环境硬性要求**：
> *   **架构**：仅支持 x64 系统与 64 位微信客户端（Shellcode 为 x64 汇编）。
> *   **权限**：调用进程若失败可能需要 **管理员身份（Administrator）** 运行。

---

## 2. API 接口说明

所有导出函数均为 C 风格接口，声明文件可见 `wx_key/include/hook_controller.h`。

| 接口函数 | 参数说明 | 详细描述 |
| :--- | :--- | :--- |
| **`InitializeHook`** | `DWORD targetPid` (微信进程ID) | **启动入口**。执行远程扫描、分配共享内存并注入 Shellcode。成功返回 `true`，失败请调 `GetLastErrorMsg`。 |
| **`PollKeyData`** | `char* keyBuf`<br>`int size` (建议 >= 65) | **获取密钥**。非阻塞检查。如果捕获到密钥，会将其格式化为 64 位 HEX 字符串写入缓冲区并返回 `true`。一次读取后自动清空。 |
| **`GetStatusMessage`** | `char* msgBuf`<br>`int size`<br>`int* outLevel` | **获取日志**。读取 DLL 内部运行日志（如“扫描成功”、“特征码未找到”等）。`outLevel` 对应：`0=Info, 1=Success, 2=Error`。 |
| **`CleanupHook`** | 无 | **清理资源**。卸载远程 Hook、释放共享内存并关闭句柄。**程序退出前务必调用**。 |
| **`GetLastErrorMsg`** | 无 | **错误诊断**。返回最近一次操作失败的具体原因。 |

---

## 3. 标准调用流程

无论使用哪种语言，集成步骤都应该要遵循以下流程：

### 第一步：定位进程
自行查找 `Weixin.exe` 的 PID（进程 ID）。

### 第二步：加载 DLL
将 `wx_key.dll` 加载到当前进程空间。
*   **Flutter**: `DynamicLibrary.open('assets/dll/wx_key.dll')`
*   **C#**: `NativeLibrary.Load("wx_key.dll")`

### 第三步：初始化 (Initialize)
调用 `InitializeHook(pid)`。
*   如果返回 `false`，通常是因为**权限不足**或**微信版本不支持**（特征码失效），请立即打印 `GetLastErrorMsg()` 排查。

### 第四步：轮询 (Polling)
启动一个后台线程或定时器（建议间隔 100ms），循环调用 `PollKeyData` 和 `GetStatusMessage`。
*   **注意**：不要在 UI 线程直接做死循环，也不要设置过长的等待时间。

### 第五步：清理 (Cleanup)
在程序关闭或不再需要功能时，**必须**调用 `CleanupHook()`。
*   如果不清理，残留在微信进程内的 Shellcode 可能会在微信后续运行时导致崩溃。

---

## 4. 代码集成示例 (C#)

以下代码展示了如何通过 P/Invoke 封装一个健壮的调用类：

```csharp
using System.Runtime.InteropServices;
using System.Text;

public class WeChatKeyDumper
{
    private const string DllName = "wx_key.dll";

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    private static extern bool InitializeHook(uint targetPid);

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    private static extern bool PollKeyData(StringBuilder keyBuffer, int bufferSize);

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    private static extern bool GetStatusMessage(StringBuilder statusBuffer, int bufferSize, out int level);

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    private static extern bool CleanupHook();

    [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr GetLastErrorMsg();

    // 启动监听任务
    public void Start(uint pid)
    {
        if (!InitializeHook(pid))
        {
            string error = Marshal.PtrToStringUTF8(GetLastErrorMsg());
            throw new Exception($"初始化失败: {error} (请尝试以管理员身份运行)");
        }

        Task.Run(async () =>
        {
            var keyBuf = new StringBuilder(128);
            var logBuf = new StringBuilder(512);
            int level;

            try
            {
                while (true)
                {
                    // 1. 尝试获取密钥
                    if (PollKeyData(keyBuf, keyBuf.Capacity))
                    {
                        Console.WriteLine($"[KEY FOUND] {keyBuf}");
                        // 拿到密钥后，可根据需求决定是否继续监听
                    }

                    // 2. 获取内部日志
                    while (GetStatusMessage(logBuf, logBuf.Capacity, out level))
                    {
                        Console.WriteLine($"[DLL Log - L{level}] {logBuf}");
                    }

                    await Task.Delay(100); // 避免 CPU 占用过高
                }
            }
            finally
            {
                CleanupHook(); // 确保线程退出时清理环境
            }
        });
    }
}
```

---

## 5. 开发者避坑指南

在实际集成中，你可能会遇到这些问题：

1.  **缓冲区溢出**：
    `PollKeyData` 返回的是 Hex 字符串，加上结束符至少需要 65 字节。C# 的 `StringBuilder` 或 C++ 的 `char[]` 分配小了会导致内存踩踏，建议给 **128 字节** 以防万一。

2.  **单例原则**：
    同一个微信进程只能被 Hook 一次。如果需要重启扫描，请先调用 `CleanupHook` 彻底释放资源，再重新 `InitializeHook`。

3.  **版本兼容性**：
    如果遇到微信更新导致无法获取密钥，通常是特征码偏移变了。此时无需修改上层代码，只需更新 DLL 源码中的 `RemoteScanner` 特征码库并重新编译 DLL 即可。

4.  **多线程安全**：
    虽然导出函数内部是线程安全的，但为了逻辑清晰，建议仅在一个专用的 Monitor 线程中进行轮询操作。
