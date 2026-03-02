给这个项目添加一个新功能“视频转写”，用于将视频/音频文件转写为文本并识别说话人

## 功能描述

- 在菜单栏中添加一个新菜单“视频转写”
- 在页面“视频转写”中，用户需要上传视频/音频文件，并选择转写语言和翻译语言，勾选“说话人识别”，点击“开始转写”按钮，会有进度条
- 转写完成后，上方是视频，下方是转写结果预览，视频可以播放，字幕和视频双向同步（可以参考已有的转写历史设计）

## 准备工作

分析目前的转写逻辑，继续使用Apple Speech 框架进行文本转写和翻译

集成FluidAudio框架进行Speaker Diarization说话人识别，需要你设计良好的架构以满足扩展性，模型的管理也需要设计好

在settings中为“说话人识别”添加单独的区域，用户需要手动下载模型，显示模型文件大小和进度，并支持切换HF_ENDPOINT=https://hf-mirror.com

## 注意

- 参考已有的转写jsonl模型设计，设计新的jsonl模型，并存放在另一个文件夹下

## 测试

为这个视频`public/panel-discussion-example.mp4`编写测试，测试转写和翻译，以及说话人识别，其中至少有3个不同的说话人

## 主要参考文档

@reference/fluidaudio-docs/Diarization/GettingStarted.md
@reference/fluidaudio-docs/Models.md 
@reference/fluidaudio-docs/README.md 