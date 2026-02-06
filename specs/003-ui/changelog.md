## UI 美化重构

### 上部区域 — 历史转录区 (`TranscriptionView`)

- 时间戳改为 monospaced 字体 + 带圆角背景的 badge 样式，更精致
- 转录文本使用 14pt regular，翻译文本使用 13pt secondary，层次分明
- 每条句子之间用细微分隔线间隔，取代之前密集的 spacing
- 移除了 volatile preview（实时文本从此视图中拆出，移至底部面板）

### 底部区域 — 统一面板 (`BottomPanelView` + `ControlBarView`)

将实时转录预览和控制栏合并为一个 `BottomPanelView`：

**上半部分 — 实时转录区：**
- 实时识别文本（italic secondary）和翻译预览显示在圆角背景框中
- 活跃监听但无文本时显示三点跳动动画 "Listening..." 指示器（`TypingIndicatorView`）
- 底部面板使用 `.ultraThinMaterial` 毛玻璃背景

**控制栏布局重新设计：**
- **中间**：大型圆形录制按钮（Apple 风格），idle 时显示红色实心圆，active 时变为红色圆角方块（停止图标），带脉冲光环动画，loading 时显示 ProgressView
- **左侧**：音频源切换（Mic/App）+ 波形可视化 + 错误指示器
- **右侧**：转录语言选择器 + 翻译开关（图标按钮，开启时高亮）+ 目标语言 + SRT 导出
- 所有按钮统一为圆角胶囊样式，填充半透明 quaternary 背景

### `AudioLevelView` 优化

- 减少到 20 条（取最近 20 个样本），宽度更紧凑
- 根据音量级别显示不同颜色（低→accent 半透明，中→accent，高→orange）
- 固定尺寸 70x16，适配新的控制栏布局

### 其他

- `ContentView` 新增 `TypingIndicatorView`（三点跳动动画）
- 空状态图标增大至 56pt thin weight，整体上移避免被底部面板遮挡
- 窗口最小尺寸调整为 640x460
- 修复了 `AnyShapeStyle` 类型擦除以解决 Swift 6 严格模式下 ternary 表达式类型不匹配

---

## UI 细节修复

- 实时转录区改为始终显示（`minHeight: 40`），不再因 idle/active 状态切换而动态出现/消失，修复了点击开始按钮后下半部分向上跳动的问题
- 音频源按钮文字从 "Mic" 改为 "Microphone"，去掉了 `maxWidth: 80` 限制
- 为所有控件添加 hover tooltip（`.help()`）：
  - 音频源按钮："Audio source"
  - 录制按钮："Start transcription" / "Stop transcription"
  - 语言选择器："Transcription language"
  - 翻译开关："Enable translation" / "Disable translation"（已有）
  - 目标语言："Translation target language"
  - 导出按钮："Export SRT"（已有）

---

## UI 细节修复 (2)

### 实时转录区显示逻辑

- 恢复为 idle 时隐藏、active/starting 时显示的逻辑
- 使用 `.animation(.easeInOut)` + `.transition(.opacity + .move)` 实现平滑的显示/隐藏动画，避免布局跳动

### 历史转录区自动滚动修复

- 将 `Color.clear` 滚动锚点从 `LazyVStack`（带 padding）内部移至 `ScrollView` 内部、`VStack` 外部
- 之前锚点在带 padding 的 VStack 内，`scrollTo("bottom")` 无法到达真正的内容底部
- 同时将 `LazyVStack` 改为 `VStack`，确保所有内容正确渲染

### App 音频源显示真实图标

- `AppAudioTarget` 模型新增 `iconData: Data?` 字段，存储 PNG 格式的 app 图标数据（32x32 缩放）
- `AppAudioCaptureService.availableApps()` 从 `NSRunningApplication.icon` 获取图标，缩放后转为 PNG Data 存储（Sendable 安全）
- 控制栏音频源按钮：选择 app 音频源时，显示该 app 的真实图标（16x16）替代通用 `app.fill` 图标
- 使用 `NSImage(data:)` → `Image(nsImage:)` 将图标数据转为 SwiftUI Image 显示
