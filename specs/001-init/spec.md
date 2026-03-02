你是一名资深 macOS App 开发者。请从零构建一个名为 **TransFlow** 的 macOS 实时语音转写应用。

---

## 技术栈

- **macOS 26.0 (Tahoe)**，Swift 6.0，严格并发安全
- **转写**：原生 Speech 框架（`SpeechAnalyzer` + `SpeechTranscriber` + `AssetInventory`）— 不使用任何第三方 ASR 框架，不使用旧版 SFSpeechRecognizer
- **翻译**：原生 Translation 框架
- **音频捕获**：AVAudioEngine（麦克风）+ ScreenCaptureKit（App 音频）
- **UI**：SwiftUI，macOS Tahoe Liquid Glass 风格
- **项目管理**：XcodeGen（`project.yml`），无第三方 package 依赖
- 项目结构由你按最佳实践组织，支持后续功能扩展

---

## 功能概述

1. **实时转写**：麦克风或指定 App 的音频 → SpeechAnalyzer → 实时预览 + 自然断句
2. **多语言**：通过 `SpeechTranscriber.supportedLocales` 动态获取所有支持的语言，用户可切换
3. **音频源切换**：麦克风 / App 音频（ScreenCaptureKit 捕获指定应用音频输出）
4. **实时翻译**：使用 Apple Translation 框架，对已完成句子和 partial 文本实时翻译
5. **SRT 导出**：将转写历史（含翻译）导出为 SRT 字幕文件

---

## 核心：SpeechEngine 转写引擎

这是整个应用最核心的部分。完整实现如下：

```swift
import Speech
import AVFoundation

/// 使用 macOS 26.0 SpeechAnalyzer + SpeechTranscriber 实现实时转写。
/// 接受 AudioChunk 流（16kHz mono Float32），输出 TranscriptionEvent 流。
final class SpeechEngine: Sendable {
    private let locale: Locale

    init(locale: Locale) {
        self.locale = locale
    }

    func processStream(_ audioStream: AsyncStream<AudioChunk>) -> AsyncStream<TranscriptionEvent> {
        let (events, continuation) = AsyncStream<TranscriptionEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(128)
        )
        let locale = self.locale

        Task {
            do {
                // 1. 创建 SpeechTranscriber
                //    - .volatileResults: 输出实时预览（非 final）文本
                //    - .fastResults: 偏向低延迟
                guard let supportedLocale = await SpeechTranscriber.supportedLocale(
                    equivalentTo: locale
                ) else {
                    continuation.yield(.error("Language \(locale.identifier) not supported"))
                    continuation.finish()
                    return
                }

                let transcriber = SpeechTranscriber(
                    locale: supportedLocale,
                    transcriptionOptions: [],
                    reportingOptions: [.fastResults, .volatileResults],
                    attributeOptions: []
                )

                // 2. 获取兼容音频格式（SpeechAnalyzer 可能需要非 16kHz 格式）
                let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                    compatibleWith: [transcriber]
                )

                // 3. 确保语音模型资产已安装（系统管理，首次使用自动下载）
                if let installRequest = try await AssetInventory.assetInstallationRequest(
                    supporting: [transcriber]
                ) {
                    try await installRequest.downloadAndInstall()
                }

                // 4. 创建 SpeechAnalyzer 并预热（减少首次结果延迟）
                let analyzer = SpeechAnalyzer(modules: [transcriber])
                try await analyzer.prepareToAnalyze(in: analyzerFormat)

                // 5. 创建输入流
                let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()

                // 6. 音频格式转换器（16kHz → analyzer 格式）
                let sourceFormat = AVAudioFormat(
                    standardFormatWithSampleRate: 16_000, channels: 1
                )!
                let converter: AVAudioConverter? = if let analyzerFormat {
                    AVAudioConverter(from: sourceFormat, to: analyzerFormat)
                } else { nil }

                // 预分配可复用输出 buffer
                let reusableBuffer: AVAudioPCMBuffer?
                if let converter, let analyzerFormat {
                    let ratio = analyzerFormat.sampleRate / sourceFormat.sampleRate
                    let capacity = AVAudioFrameCount(16_000 * 0.25 * ratio) + 64
                    reusableBuffer = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity)
                } else { reusableBuffer = nil }

                // 7. 先启动结果消费（避免丢失早期结果）
                //    result.isFinal == true  → 句子确定（sentenceComplete）
                //    result.isFinal == false → 实时预览（partial）
                //    result.text 是 AttributedString，需 String(result.text.characters) 转纯文本
                let resultTask = Task(priority: .userInitiated) {
                    do {
                        for try await result in transcriber.results {
                            let text = String(result.text.characters)
                            if result.isFinal {
                                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty {
                                    continuation.yield(.sentenceComplete(
                                        TranscriptionSentence(timestamp: Date(), text: trimmed)
                                    ))
                                    continuation.yield(.partial(""))
                                }
                            } else {
                                continuation.yield(.partial(text))
                            }
                        }
                    } catch {
                        continuation.yield(.error("Speech error: \(error.localizedDescription)"))
                    }
                }

                // 8. 启动自治分析（立即返回）
                try await analyzer.start(inputSequence: inputSequence)

                // 9. 喂入音频：累积 ~200ms 再批量送入，减少格式转换开销
                var accumulator: [Float] = []
                let batchThreshold = Int(16_000 * 0.2)

                for await chunk in audioStream {
                    accumulator.append(contentsOf: chunk.samples)
                    guard accumulator.count >= batchThreshold else { continue }

                    if let input = Self.convertToAnalyzerInput(
                        samples: accumulator, converter: converter, reusableBuffer: reusableBuffer
                    ) {
                        inputBuilder.yield(input)
                    }
                    accumulator.removeAll(keepingCapacity: true)
                }

                // flush 剩余
                if !accumulator.isEmpty, let input = Self.convertToAnalyzerInput(
                    samples: accumulator, converter: converter, reusableBuffer: reusableBuffer
                ) {
                    inputBuilder.yield(input)
                }

                // 10. 完成
                inputBuilder.finish()
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                resultTask.cancel()

            } catch {
                continuation.yield(.error("Engine error: \(error.localizedDescription)"))
            }
            continuation.finish()
        }

        return events
    }

    // MARK: - Helpers

    /// 将 Float32 samples 转换为 AnalyzerInput（含格式转换）
    private static func convertToAnalyzerInput(
        samples: [Float],
        converter: AVAudioConverter?,
        reusableBuffer: AVAudioPCMBuffer?
    ) -> AnalyzerInput? {
        guard let pcmBuffer = createPCMBuffer(from: samples) else { return nil }

        if let converter, let reusableBuffer {
            reusableBuffer.frameLength = 0
            var error: NSError?
            nonisolated(unsafe) var consumed = false
            converter.convert(to: reusableBuffer, error: &error) { _, outStatus in
                if consumed { outStatus.pointee = .noDataNow; return nil }
                consumed = true; outStatus.pointee = .haveData; return pcmBuffer
            }
            guard error == nil, reusableBuffer.frameLength > 0 else { return nil }
            return AnalyzerInput(buffer: reusableBuffer)
        } else {
            return AnalyzerInput(buffer: pcmBuffer)
        }
    }

    /// 从 Float32 samples 创建 16kHz mono PCM buffer
    private static func createPCMBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let channelData = buffer.floatChannelData else { return nil }
        samples.withUnsafeBufferPointer { ptr in
            channelData[0].initialize(from: ptr.baseAddress!, count: samples.count)
        }
        return buffer
    }
}
```

### 关键 API 速查

| API | 说明 |
|-----|------|
| `SpeechTranscriber(locale:transcriptionOptions:reportingOptions:attributeOptions:)` | 创建转写器 |
| `.fastResults` | 低延迟优先 |
| `.volatileResults` | 输出实时预览（非 final）结果 |
| `result.isFinal` | true=句子确定，false=volatile 预览 |
| `result.text` | AttributedString，用 `String(result.text.characters)` 转纯文本 |
| `SpeechTranscriber.supportedLocale(equivalentTo:)` | 查找匹配的支持语言 |
| `SpeechTranscriber.supportedLocales` | 所有支持的语言（动态获取） |
| `AssetInventory.assetInstallationRequest(supporting:)` | nil=已安装，否则需下载 |
| `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)` | 获取兼容音频格式 |
| `analyzer.prepareToAnalyze(in:)` | 预热模型 |
| `analyzer.start(inputSequence:)` | 启动自治分析 |
| `analyzer.finalizeAndFinishThroughEndOfInput()` | 结束分析 |
| `AnalyzerInput(buffer:)` | 包装 AVAudioPCMBuffer |

---

## 音频捕获

### 麦克风 (AVAudioEngine)

- 使用 `AVAudioEngine` 的 `inputNode.installTap` 捕获麦克风
- 通过 `AVAudioConverter` 转换为 **16kHz mono Float32**
- 每 ~100ms 输出一个 `AudioChunk`（含 samples + 归一化音量 level + timestamp）
- 音量计算：RMS → dB → 归一化到 0-1
- 权限请求：`AVAudioApplication.requestRecordPermission()`
- 返回 `(stream: AsyncStream<AudioChunk>, stop: @Sendable () -> Void)`

### App 音频 (ScreenCaptureKit)

- 通过 `SCShareableContent` 枚举可用的 GUI 应用（排除自身、隐藏应用）
- 与 `NSWorkspace.shared.runningApplications` 交叉验证，获取应用图标
- 使用 `SCStream` + `SCContentFilter` 捕获目标应用音频
- 配置：`capturesAudio = true`，`excludesCurrentProcessAudio = true`，最小化视频开销（2x2 像素，1fps）
- 通过 `SCStreamOutput` delegate 接收 `CMSampleBuffer`，转换为 16kHz mono Float32 `AudioChunk`
- 需要 Screen & System Audio Recording 权限（系统自动提示）

---

## 翻译 (Apple Translation)

- 通过 SwiftUI `.translationTask(configuration, action:)` 获取 `TranslationSession`
- 不能直接创建 session，必须通过此修饰符
- 当翻译开关开启或目标语言变化时，`Configuration.invalidate()` + 重新创建触发新 session
- 对已完成句子直接翻译
- 对 partial 文本使用 ~300ms debounce 翻译（避免频繁调用）
- 支持批量翻译（`session.translate(batch:)`）

---

## ViewModel 核心逻辑

`@Observable @MainActor` 的 ViewModel 协调所有服务：

### 核心流程

1. **初始化**：请求麦克风权限
2. **语言切换**：停止监听 → 重建 `SpeechEngine(locale:)` → 可选检查资产状态
3. **开始监听**：
   - 根据音频源启动 AudioCaptureService 或 AppAudioCaptureService
   - 创建 SpeechEngine → `processStream(audioStream)`
   - fork 音频流：一路给引擎转写，一路更新 UI 音量显示
   - 消费 `TranscriptionEvent` 流更新 UI（partial → 预览区，sentenceComplete → 历史区）
4. **停止监听**：停止音频捕获，flush 剩余 partial text 为最终句子
5. **翻译联动**：sentenceComplete 时自动翻译，partial text debounce 翻译

### 关键状态

```
sentences: [TranscriptionSentence]  // 已完成句子历史
currentPartialText: String          // 实时预览
listeningState: ListeningState      // idle/starting/active/stopping
audioLevel: Float                   // 当前音量 0-1
audioLevelHistory: [Float]          // 波形历史
audioSource: AudioSourceType        // 麦克风 or App 音频
selectedLanguage                    // 当前转写语言
isTranslationEnabled: Bool          // 翻译开关
translationTargetLanguage           // 翻译目标语言
currentPartialTranslation: String   // partial 文本的翻译
errorMessage: String?               // 错误提示
```

---

## 界面布局

```
┌─────────────────────────────────────────┐
│                                         │
│           转写区域（占满上方）              │
│                                         │
│   [14:32:05] This is a sentence.        │
│              这是一个句子。               │
│   [14:32:08] Another complete sentence. │
│              另一个完整句子。              │
│                                         │
│   ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄   │
│   This is being spoken right now...     │  ← volatile 预览（灰色/斜体）
│   正在实时翻译...                        │  ← 翻译预览
│                                         │
├─────────────────────────────────────────┤
│  ⏺ Start │ 🎤 Mic ▾ │ EN ▾ │ 🌐 → ZH ▾ │  ← 底部控制栏（合并）
│  ▁▂▃▅▃▂▁  │  2ms     │ 导出  │           │  ← 波形 + 延迟 + 导出
└─────────────────────────────────────────┘
```

### 布局说明

- **上方转写区域**占据窗口绝大部分空间（ScrollView + 自动滚动到底部）
  - 已完成句子：时间戳 + 原文 + 翻译文本（如启用）
  - 底部 volatile 预览区：灰色/斜体，显示正在说的内容
- **底部控制栏**合并为一行，包含：
  - 开始/停止监听按钮
  - 音频源切换（麦克风 / App 音频选择器）
  - 转写语言选择器
  - 翻译开关 + 目标语言选择器
  - 小型音量波形可视化
  - 延迟显示
  - SRT 导出按钮
  - 错误提示

### 菜单快捷键

- `Cmd+K`：清空历史
- `Cmd+Shift+E`：导出 SRT

### 设计原则

- macOS Tahoe Liquid Glass 风格
- 深色/浅色模式自适应
- UI 细节自由发挥，保持简洁美观
- 重点是功能完整可用

---

## 注意事项

1. SpeechAnalyzer 是 **actor** 类型，SpeechTranscriber 是 Sendable class — 注意 Swift 6 并发安全
2. 音频捕获输出 16kHz mono Float32，SpeechAnalyzer 可能需要不同格式 — 必须用 `bestAvailableAudioFormat` 获取并转换
3. 语音模型资产由系统管理，下载后 app 间共享，长期不用可能被系统清理
4. Translation session 只能通过 SwiftUI `.translationTask` 修饰符获取
5. ScreenCaptureKit 需要 Screen & System Audio Recording 权限
6. 所有 Speech 框架新 API（SpeechAnalyzer, SpeechTranscriber, AssetInventory, AnalyzerInput 等）均为 macOS 26.0+ 专属
