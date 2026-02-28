# 020 Bug 修复与优化 — Changelog

## v1

### Fixed
- **JSONL startTime/endTime 相同** — 使用 `SpeechModuleResult.range` (CMTimeRange) 从语音分析器获取精确的音频时间范围，替代之前用 `Date()` 估算的时间戳。`start_time` 现在是语音实际开始时刻，`end_time` 是语音实际结束时刻
- **设置页面模型列表嵌套滚动** — 移除 Speech Models 区域内部的 `ScrollView` 和 `maxHeight: 200` 约束，模型列表直接内联在外部页面 ScrollView 中

### Changed
- `TranscriptionSentence` 新增 `startTimestamp` 属性，区分语音起始时间（`startTimestamp`）和语音结束时间（`timestamp`）
- `SpeechEngine` 为每个 `AnalyzerInput` 提供基于累计帧数的 `bufferStartTime: CMTime`，建立精确的分析器时间轴
- `SpeechEngine` 从 `result.range` 提取 `CMTimeRange`，结合 session 起始锚点转换为绝对 `Date`
- `JSONLContentEntry.init(sentence:)` 移除 `endTime:` 参数，直接从 sentence 的两个时间戳获取
- `JSONLStore.appendEntry` 签名简化，移除 `endTime` 参数
- `SessionAudioPlayer` 直接使用 `entry.startTime` 和 `entry.endTime` 分别匹配所属录音段计算播放偏移，不再从前一条目的 endOffset 推断 startOffset

### Files Modified
- `Models/TranscriptionModels.swift` — `TranscriptionSentence` 新增 `startTimestamp: Date` 属性
- `Models/JSONLModels.swift` — `JSONLContentEntry.init(sentence:)` 使用 `startTimestamp`/`timestamp`，移除 `endTime` 参数
- `Services/SpeechEngine.swift` — 引入 `CoreMedia`；追踪 `cumulativeOutputFrames` 提供 `bufferStartTime`；从 `result.range` 提取时间戳；`convertToAnalyzerInput` 返回 `(AnalyzerInput, AVAudioFrameCount)` 元组
- `Services/JSONLStore.swift` — `appendEntry(sentence:)` 签名简化
- `Services/SessionAudioPlayer.swift` — 重写 entry offset 计算，分别从 `startTime`/`endTime` 匹配录音段
- `ViewModels/TransFlowViewModel.swift` — 新增 `partialStartTimestamp` 用于 stopListening flush 场景
- `Views/SettingsView.swift` — `speechModelsContent` 移除 `ScrollView` 和 `.frame(maxHeight: 200)`
