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
