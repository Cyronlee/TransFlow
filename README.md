<div align="center">
  <img src="public/logo.png" alt="TransFlow Logo" width="128" height="128">
  <h1>TransFlow</h1>
  <p><strong>macOS 实时语音转录与翻译工具，完全离线，注重隐私</strong></p>

  [![GitHub release](https://img.shields.io/github/v/release/Cyronlee/TransFlow?style=flat-square)](https://github.com/Cyronlee/TransFlow/releases)
  [![License](https://img.shields.io/github/license/Cyronlee/TransFlow?style=flat-square)](LICENSE)
  [![Platform](https://img.shields.io/badge/platform-macOS%2015.0+-blue?style=flat-square&logo=apple)](https://github.com/Cyronlee/TransFlow)
  [![Swift](https://img.shields.io/badge/Swift-6.0-orange?style=flat-square&logo=swift)](https://swift.org)
  [![SwiftUI](https://img.shields.io/badge/SwiftUI-✓-blue?style=flat-square&logo=swift)](https://developer.apple.com/swiftui/)
  [![GitHub stars](https://img.shields.io/github/stars/Cyronlee/TransFlow?style=flat-square)](https://github.com/Cyronlee/TransFlow/stargazers)
  [![GitHub issues](https://img.shields.io/github/issues/Cyronlee/TransFlow?style=flat-square)](https://github.com/Cyronlee/TransFlow/issues)
  [![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen?style=flat-square)](https://github.com/Cyronlee/TransFlow/pulls)

  [English](README_EN.md) | **中文**

  <a href="https://github.com/Cyronlee/TransFlow/releases">
    <img src="https://img.shields.io/badge/Download-DMG%20Installer-blue?style=for-the-badge&logo=apple" alt="Download">
  </a>
</div>

---

<div align="center">
  <img src="public/demo-1-zh.png" alt="TransFlow 演示" width="800">
</div>

## ✨ 功能特性

- **🎙️ 实时语音转录** — 基于 Apple Speech 框架，利用 Neural Engine 硬件加速，转录准确率高，适用于会议、讲座、对话等长时间音频场景
- **🌐 实时翻译** — 使用 Apple Translation 框架，转录结果实时翻译，支持 macOS 内置的所有语言
- **🔊 应用音频捕获** — 通过 ScreenCaptureKit 捕获其他应用的音频进行转录，轻松转录在线会议和视频
- **🔒 隐私优先** — 语音识别与翻译完全在设备端运行（on-device），无需联网
- **📜 历史记录** — 自动保存转录会话，支持浏览、预览、重命名和删除历史记录
- **📤 导出支持** — 支持导出为 SRT 字幕和 Markdown 格式
- **⚙️ 设置与定制** — 配置语言偏好和外观模式（浅色/深色/跟随系统）
- **🪶 轻量小巧** — 应用体积不到 800KB，小而美，即装即用

## 🛠️ 技术栈

| 技术 | 说明 |
|------|------|
| **Swift 6.0** | 主要开发语言，使用最新的并发特性 |
| **SwiftUI** | 声明式 UI 框架，原生 macOS 界面 |
| **Speech Framework** | Apple 语音识别框架，Neural Engine 硬件加速，完全离线 |
| **Translation Framework** | Apple 翻译框架，设备端翻译，支持 macOS 所有内置语言 |
| **AVFoundation** | 音频捕获与处理 |
| **ScreenCaptureKit** | 捕获其他应用的音频流 |
| **MVVM 架构** | 使用 `@Observable` 的现代 SwiftUI 架构模式 |

## 📦 安装

### 系统要求

- macOS 15.0 (Sequoia) 或更高版本
- Apple Silicon (arm64) 或 Intel (x86_64)

### 下载安装

1. 前往 [Releases 页面](https://github.com/Cyronlee/TransFlow/releases) 下载最新的 DMG 安装包
2. 打开 DMG 文件，将 TransFlow 拖入 Applications 文件夹
3. 首次打开时，如遇到安全提示，请前往「系统设置 → 隐私与安全性」中允许运行

### 从源码构建

```bash
git clone https://github.com/Cyronlee/TransFlow.git
cd TransFlow
open TransFlow/TransFlow.xcodeproj
```

在 Xcode 中选择 TransFlow target，点击运行即可。

## 🚀 快速开始

1. 启动 TransFlow，授予麦克风权限
2. 选择音频来源（麦克风或应用音频）
3. 选择转录语言和翻译目标语言
4. 点击开始按钮，实时查看转录和翻译结果
5. 会话自动保存，可在历史记录中回顾

## ⌨️ 快捷键

| 快捷键 | 功能 |
|--------|------|
| `⌘ K` | 清除当前转录 |
| `⌘ ⇧ E` | 导出为 SRT 字幕 |

## 🗺️ Roadmap

- [ ] 支持 Whisper 等第三方语音模型
- [ ] 识别讲话人
- [ ] 自定义样式
- [ ] 自定义快捷键
- [ ] 欢迎贡献更多

## 🤝 参与贡献

欢迎提交 Issue 和 Pull Request！

1. Fork 本仓库
2. 创建你的功能分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 提交 Pull Request

### 报告问题

如果你发现了 Bug 或有功能建议，请 [创建 Issue](https://github.com/Cyronlee/TransFlow/issues/new)。

## 📄 许可证

本项目采用 MIT 许可证 — 详见 [LICENSE](LICENSE) 文件。

## ⭐ Star History

如果你觉得 TransFlow 有用，请给我们一个 Star ⭐，这是对我们最大的支持！

---

<div align="center">
  <sub>用 ❤️ 打造 by <a href="https://github.com/Cyronlee">Cyronlee</a></sub>
</div>
