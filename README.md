# 微信数据库key提取工具

[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows-lightgrey.svg)](https://www.microsoft.com/windows)
[![Flutter](https://img.shields.io/badge/Flutter-3.9.2+-02569B.svg?logo=flutter)](https://flutter.dev)

> **重要声明**: 本项目仅供技术研究和学习使用，严禁用于任何恶意或非法目的。如果这个项目对你有帮助的话，请给我们一个Star❤️

## 项目简介

本项目使用注入DLL获取微信数据库密钥的解决方案，解决了当前主流内存搜索key的工具（如 dumprs、chatlog 等）在微信 4.1 及以上版本中失效的问题

![效果截图](app.jpg)

## 小提示

欢迎大家看看我的这个项目：[EchoTrace - 一个微信聊天记录导出与分析，年度报告应用](https://github.com/ycccccccy/echotrace)




## 支持版本

- 4.1.2.17 (**2025-10-22**)
- 4.1.2.16 (**2025-10-20**)
- 4.1.2.11 (**2025-10-14**）
- 4.1.2.9 (**2025-10-13**）
- 4.1.1.19 (**2025-09-30**）
- 4.1.0.34 (**2025-09-05**)

> **提示**
>
> 建议始终使用最新的官方微信版本
>
> 我们会在官方发布最新版本后不久更新适配

## 快速开始

1. **下载发布版本**
   从 Releases 页面下载最新版本的提取工具的压缩包

2. **运行**
   以管理员身份打开解压后压缩包中的wx_key.exe或自行编译得到的wx_key.exe

> **注意**：请不要把工具文件夹和dll放在任何中文字符的目录下

### 使用指南

1. **启动应用**: 应用启动后将自动检测微信的版本
2. **开始提取**：检测完版本后将会尝试自动下载Dll，若版本不支持将无法继续
3. **查看密钥**：如果版本支持，在下载完将自动注入获取密钥，按照提示登录微信即可查看密钥，获取完成后回到应用内即可查看，微信崩溃是正常的

## 项目架构

### 目录结构

```
wx_key/
├── lib/                          # Flutter 应用核心代码
│   ├── main.dart                 # 应用入口及主界面
│   └── services/                 # 核心服务模块
│       ├── dll_injector.dart     # DLL注入服务
│       ├── key_storage.dart      # 密钥存储管理
│       └── pipe_listener.dart    # 进程通信监听
└── dllmain.cpp                   # DLL获取key的实现
```

## 开发构建

### 构建流程

```bash
# 1. 克隆项目
git clone https://github.com/ycccccccy/wx_key.git
cd wx_key

# 2. 安装依赖
flutter pub get

# 3. 构建发布版本
flutter build windows --release

# 4. 输出位置
# build/windows/runner/Release/wx_key.exe
```

### 开发调试

```bash
# 开发模式运行
flutter run -d windows

# 调试模式构建
flutter build windows --debug

# 性能分析
flutter run --profile
```

## 许可证与免责声明

### 许可证

本项目采用 MIT 许可证，详见 [LICENSE](LICENSE) 文件。

MIT 许可证允许您自由使用、修改和分发本软件，但需要保留版权声明和许可证文本。

### 免责声明

> **重要**: 本工具仅用于技术研究和学习目的，旨在提供一个探索性的解决方案。

**使用须知**:
- 任何使用本工具产生的后果与责任，均由使用者自行承担
- 开发者不对因使用本工具而导致的任何损失负责
- 使用者必须确保其使用行为符合当地法律法规
- 严禁将本工具用于任何商业或恶意目的

### 贡献指南

欢迎提交 Issue 和 Pull Request 来改进本项目：

1. Fork 本仓库
2. 创建分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

---

<div align="center">

**请负责任地使用本工具，遵守相关法律法规**

Made for educational purposes ❤️

</div>
