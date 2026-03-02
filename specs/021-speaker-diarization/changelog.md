# Changelog — 021 Speaker Diarization

## 2026-03-02 — Iteration 3: UX 优化

### 修复
- **Picker 报错**：修复 `Picker: the selection "en-US (fixed)" is invalid` 错误。根因是 `Locale(identifier: "en-US")` 与 `availableLanguages` 中通过 `minimalIdentifier` 生成的 `Locale("en")` 不相等。改用 String identifier 作为 Picker tag，彻底避免 Locale 相等性问题。
- **默认语言**：转写默认语言改为 English（`"en"`）。

### 改进
- **视频播放控件**：移除自定义播放控件（play/pause、slider、时间显示），改用 `AVKit.VideoPlayer` 自带的系统播放控件。保留右上角"重新转写"按钮。通过 `addPeriodicTimeObserver` 同步字幕高亮。
- **配置记忆**：所有视频转写配置选项（转写语言、是否翻译、翻译目标语言、是否启用说话人识别、说话人灵敏度）通过 `AppSettings` 持久化到 `UserDefaults`，下次打开自动恢复。

### 文件变更
- `AppSettings.swift` — 新增 `videoSourceLanguage`、`videoEnableTranslation`、`videoTargetLanguage`、`videoEnableDiarization` 持久化属性
- `VideoTranscriptionViewModel.swift` — 改用 identifier-based 语言选择；从 AppSettings 读取初始配置；启动转写时保存配置；用 `addPeriodicTimeObserver` 替代 Timer
- `VideoTranscriptionView.swift` — Picker 改用 String tag；移除自定义播放控件；保留系统内置控件

---

## 2026-03-02 — Iteration 2: 说话人识别优化

### 新增
- **说话人灵敏度滑块**：在视频转写配置中新增"说话人灵敏度"滑块（0.50–0.95），映射到 `OfflineDiarizerConfig.clusteringThreshold`。值越高，识别出的说话人越多，适用于相似声音（如两个女性）的场景。参数持久化到 `UserDefaults`。
- **智能断句拆分**：当一段转写文本跨越多个说话人 diarization 片段时，不再简单按时间比例硬切文本，而是在标点符号（`. , ! ? 。，！？` 等）处寻找最佳拆分点，退而求其次找空格，确保拆分自然。

### 文件变更
- `AppSettings.swift` — 新增 `diarizationSensitivity` 持久化属性
- `DiarizationService.swift` — `performDiarization` 接受 `clusteringThreshold` 参数
- `VideoTranscriptionViewModel.swift` — 暴露灵敏度参数；重写 `mergeResults` 实现说话人边界拆分 + 标点对齐
- `VideoTranscriptionView.swift` — 新增灵敏度滑块 UI
- `Localizable.xcstrings` — 新增 4 条国际化字符串（说话人灵敏度相关）

---

## 2026-03-02 — Iteration 1: 初始实现

### 新增
- 视频转写完整功能：文件上传、音频提取、Apple Speech 转写、FluidAudio 说话人识别、翻译、JSONL 持久化
- 侧边栏"视频转写"入口
- Settings 中说话人识别模型管理（下载、状态、HF 镜像）
- 集成测试（音频提取、说话人分配、JSONL 往返）
