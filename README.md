# 聊天工具密钥提取工具

[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows-lightgrey.svg)](https://www.microsoft.com/windows)
[![Flutter](https://img.shields.io/badge/Flutter-3.9.2+-02569B.svg?logo=flutter)](https://flutter.dev)

> **重要声明**: 本项目仅供技术研究和学习使用，严禁用于任何恶意或非法目的。如果这个项目对你有帮助的话，请给我们一个Star❤️

## 项目简介

本项目提供了一种通过DLL注入技术获取某聊天工具数据库密钥的解决方案。针对当前主流内存搜索key的工具（如 dumprs、chatlog 等）在目标软件 4.1 及以上版本中失效的问题，当前方案相对更稳定


## 技术文档

- [4.1版本密钥分析研究报告](wx4.1_analysis.md) - 详细的技术分析和实现原理

## 项目架构

### 目录结构

```
wx_key/
├── lib/                          # Flutter 应用核心代码
│   ├── main.dart                 # 应用入口及主界面实现
│   └── services/                 # 核心服务模块
│       ├── dll_injector.dart     # DLL注入服务
│       ├── key_storage.dart      # 密钥存储管理
│       └── pipe_listener.dart    # 进程通信监听
├── pubspec.yaml                  # 项目配置和依赖管理
└── dllmain.cpp                   # DLL注入核心实现
```

## 快速开始

### 系统要求

- **操作系统**: Windows 10/11 (64位)
- **权限要求**: 管理员权限
- **目标软件**: 某小而美聊天工具 4.0+ 版本

### 安装步骤

1. **下载发布版本**
   ```bash
   # 从 Releases 页面下载最新版本
   # 包含: wx_key.exe 和 wx_key.dll
   ```

2. **运行**
   以管理员身份打开下载或自行编译的wx_key.exe

### 操作指南

1. **启动检测**: 应用启动后自动检测目标进程状态
2. **执行注入**: 点击"开始注入"按钮，系统将弹出CMD窗口显示详细过程
3. **查看结果**: 在主界面日志区域查看提取的密钥信息

## 开发构建

### 构建流程

```bash
# 1. 克隆项目
git [clone https://github.com/ycccccccy/wx_key](https://github.com/ycccccccy/wx_key.git)
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
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

---

<div align="center">

**请负责任地使用本工具，遵守相关法律法规**

Made for educational purposes ❤️

</div>
