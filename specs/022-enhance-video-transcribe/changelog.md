# Changelog

## 2026-03-02 — 第二轮优化

### 改动

- **术语统一**：所有"音视频"改为"视频"，英文对应从 "Media" 改为 "Video"
- **历史列表过滤**：从分段选择器（Segmented Picker）改为下拉菜单（Menu Picker），与条目数和编辑按钮同行显示
- **列表颜色区分**：视频相关条目使用蓝色标识（badge + 时长），实时相关条目使用橙色标识（badge + 时长）
- **预览区域布局**：将工具栏移至最顶部，视频/音频播放器放在工具栏下方（实时转写和视频转写详情均适用）
- **说话人标签本地化**：不再使用 "speaker 0" 等原始 ID，改为本地化显示：中文"说话人 1"，英文"Speaker 1"（编号从 1 开始）
- **说话人重命名**：在转写预览区域点击说话人标签可弹窗重命名，修改同步写入 JSONL 文件

### 涉及文件

- `Localizable.xcstrings` — 更新"音视频"→"视频"，新增 `speaker.label_prefix`、`speaker.rename_title`、`speaker.rename_prompt` 本地化字符串
- `HistoryView.swift` — 过滤器改为下拉选、颜色区分、工具栏置顶、说话人重命名弹窗
- `VideoTranscriptionView.swift` — `VideoSegmentRow` 说话人标签本地化和可点击重命名
- `VideoTranscriptionModels.swift` — 新增 `SpeakerDisplayName` 工具枚举
- `VideoJSONLStore.swift` — 新增 `renameSpeaker(in:from:to:)` 方法
- `TranscriptionExporter.swift` — 导出时使用本地化说话人名称

## 2026-03-01 — 初始实现

- 菜单栏重命名和图标统一
- 说话人识别自动检测中国地区使用镜像
- 转写历史页面统一展示实时/视频转写，编辑模式批量删除
- 视频转写历史预览（视频播放器 + 字幕同步 + 导出）
- 转写完成自动跳转历史页面
- JSONL 记录原始文件路径
