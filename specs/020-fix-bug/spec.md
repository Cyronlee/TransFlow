# 020 Bug 修复与优化

## 问题 1：JSONL content 的 startTime 和 endTime 相同

### 根因

`SpeechEngine` 在句子完成时创建 `TranscriptionSentence(timestamp: Date())`，`JSONLContentEntry` 的 `startTime` 使用该 timestamp，`endTime` 默认也是 `Date()`——两者几乎是同一时刻。

即使将 `startTime` 改为"收到第一个 partial 结果的时刻"，由于音频累积（~200ms 批次）+ 语音分析器处理延迟，`startTime` 仍会比实际说话时机晚数秒。

### 方案

利用 Apple SpeechAnalyzer 框架的精确音频时间轴：

1. **提供 `bufferStartTime`**：向 `AnalyzerInput` 传入 `CMTime`，基于累计输出帧数和采样率计算，让分析器建立准确的内部时间线
2. **读取 `result.range`**：`SpeechTranscriber.Result` 遵循 `SpeechModuleResult` 协议，其 `range: CMTimeRange` 属性给出该转录结果对应的精确音频时间范围
3. **锚点转换**：记录 session 开始的 `Date` 作为 `CMTime(0)` 的墙钟锚点，将 `range.start` / `range.end` 转换为绝对 `Date`

### 数据模型变更

- `TranscriptionSentence` 新增 `startTimestamp: Date`（语音起始）与 `timestamp: Date`（语音结束）
- `JSONLContentEntry.init(sentence:)` 使用 `startTimestamp` → `start_time`，`timestamp` → `end_time`
- 移除 `JSONLContentEntry` 初始化器的 `endTime:` 参数
- `SessionAudioPlayer` 直接使用 `entry.startTime` 和 `entry.endTime` 计算播放偏移，不再从前一条目推断

## 问题 2：设置页面模型区域内部滚动

### 根因

`speechModelsContent` 使用 `ScrollView { ... }.frame(maxHeight: 200)` 包裹模型列表，导致在外层 ScrollView 内嵌套了一个独立滚动区域，交互体验差。

### 方案

移除内部 `ScrollView` 和 `maxHeight` 约束，改为直接 `VStack`，让模型列表内联在外部页面滚动视图中。
