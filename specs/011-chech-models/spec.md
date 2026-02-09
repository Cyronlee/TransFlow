在 App 中处理 Apple Speech 模型资产检查和下载逻辑，以提供顺畅的用户体验。参考 Apple 开发者文档的 Speech 框架部分以获取实现细节。

- 下载过程由 App 管理，通常在首次使用时自动触发（例如显示进度条）
- 在设置页面显示模型状态

以下是 macOS（包括 macOS 26 / Tahoe 版本）最新 Apple Speech API（主要是 SpeechAnalyzer 和 SpeechTranscriber）的官方相关文档 URL。这些来自 Apple Developer 网站，是最权威的参考：

- **Speech 框架总览**（包含所有 Speech API 的入口，包括新 API）：  
  https://developer.apple.com/documentation/speech

- **SpeechAnalyzer 类**（核心分析器，管理会话和模块）：  
  https://developer.apple.com/documentation/speech/speechanalyzer

- **SpeechTranscriber 类**（语音转文字转录模块，支持日常对话等场景）：  
  https://developer.apple.com/documentation/speech/speechtranscriber

- **AssetInventory 类**（管理模型资产的下载和安装，用户首次使用非预装语言时会涉及这个）：  
  https://developer.apple.com/documentation/speech/assetinventory

- **集成指南：Bringing advanced speech-to-text capabilities to your app**（包含示例代码和使用流程，强烈推荐先看这个）：  
  https://developer.apple.com/documentation/Speech/bringing-advanced-speech-to-text-capabilities-to-your-app

- **WWDC25 相关视频和资源**（介绍新 API 的 session，包含代码 demo）：  
  https://developer.apple.com/videos/play/wwdc2025/277

这些文档中会详细说明模型资产（model assets）的检查、下载逻辑（通过 AssetInventory），尤其是对于中文等语言，用户很可能需要 App 引导下载（通常几百 MB 到 1GB+，视语言而定）。建议你直接访问这些页面查看最新 API 变化和代码示例。
