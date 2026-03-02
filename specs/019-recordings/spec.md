# 019 转写同时录音

## 目标

在转写的同时录制音频，用于后期回放、精校准和说话人识别等场景。

## 功能设计

### 录音

- 每次点击开始转写时，自动开始录音
- 每次点击停止转写时，自动停止录音并保存
- 同一个转写 session（JSONL 文件）可以包含多段录音
- 录音文件格式为 M4A (AAC)，16kHz 单声道
- 录音文件命名：`rec_<yyyy-MM-dd_HH-mm-ss>.m4a`（每次开始录音生成唯一文件名）
- 录音保存路径：`~/Library/Application Support/<bundleID>/recordings/`

### JSONL 格式

在现有 `metadata` 和 `content` 类型基础上，新增两种行类型：

**`recording_start`** — 标记录音段开始：
```json
{"type":"recording_start","recording_file":"rec_2025-02-28_14-30-00.m4a","timestamp":"<ISO8601>"}
```

**`recording_stop`** — 标记录音段结束：
```json
{"type":"recording_stop","recording_file":"rec_2025-02-28_14-30-00.m4a","timestamp":"<ISO8601>","duration_ms":15000}
```

`content` 条目不存储音频偏移量。字幕与录音的时间对应关系在播放时动态计算——通过对比 `recording_start` 的 timestamp 和 content 的 `start_time` 可算出字幕在合并时间线上的位置。

### 历史回放

- 在历史预览区域底部添加音频播放条：
  - 播放/暂停 + 停止按钮在左侧
  - 进度条（Slider）带有段落起始标记
  - 当前时间和总时长标签
- 多段录音自动合并为一条连续时间线播放
- 进度条上用橙色竖线标记每段录音的起始位置（第一段除外）
- 播放时根据时间戳自动高亮当前字幕行，并自动滚动
- 点击字幕行的**时间戳区域**可跳转到对应录音位置并开始播放
- 有录音的会话在列表和详情工具栏中显示录音总时长（而非简单的波形图标）

### 数据流

```
AudioChunk stream (16kHz mono Float32)
  ├─ engineContinuation  → SpeechEngine (转写)
  ├─ levelContinuation   → UI 音量指示
  └─ recordingContinuation → AudioRecordingService (写入 M4A)
```

录音复用现有音频采集流，不需要额外的音频引擎或权限。
