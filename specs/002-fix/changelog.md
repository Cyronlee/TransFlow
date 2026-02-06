## 问题 1: App 音频源无法转录

**根本原因:** `AppAudioCaptureService` 有三个关键缺陷:

1. **错误的 SCContentFilter** — 使用了 `SCContentFilter(desktopIndependentWindow:)` 只捕获单个窗口，而不是应用的整体音频输出。改为使用 `SCContentFilter(display:including:exceptingWindows:)` 来捕获目标应用的所有音频。

2. **缺少采样率转换** — ScreenCaptureKit 原生输出 48kHz 音频，但代码直接设置 `sampleRate = 16_000` 并且在 `SCStreamOutput` 回调中没有做格式转换。SpeechEngine 期望接收 16kHz mono Float32 数据。修复后改为按 48kHz 原生采样，然后用 `AVAudioConverter` 正确转换到 16kHz。

3. **force unwrap 崩溃** — `formatDesc!` 强制解包可能导致崩溃。用安全的 `guard let` 替换。

4. **缺少 `.screen` 输出处理器** — 没有注册 screen output handler 导致 ScreenCaptureKit 持续输出 "stream output NOT found. Dropping frame" 错误日志。

## 问题 2: 翻译功能开启就崩溃

**根本原因:** `TranslationSession` 在使用前没有调用 `prepareTranslation()`:

1. **缺少 session 准备** — `.translationTask` 提供的 `TranslationSession` 在翻译前需要先调用 `prepareTranslation()` 来下载语言包（如果需要）。原代码直接调用 `setSession()` 后就开始翻译，可能导致崩溃。

2. **配置生命周期问题** — 禁用翻译时没有清理 session 和相关状态，导致状态不一致。

修复后将 `setSession()` 改为 `handleSession()`, 内部先 `await prepareTranslation()` 再保存 session，并在禁用时正确清理所有状态。

**问题:** 翻译时频繁弹出 "the language could not be detected" 的选择语言弹窗。

**原因:** `TranslationService.sourceLanguage` 默认为 `nil`，传给 `TranslationSession.Configuration(source: nil, ...)` 时，Translation 框架会尝试自动检测源语言。当短句或 partial text 不足以让框架识别语言时，就会弹出选择弹窗。

**修复内容:**

1. **添加了语言映射方法** `TranslationService.translationLanguage(from:)` — 将转录使用的 `Locale`（如 `"en-US"`, `"zh-Hans-CN"`）映射为 Translation 框架需要的 `Locale.Language`（如 `"en"`, `"zh-Hans"`）。特别处理了中文的简繁体（`zh-Hans` / `zh-Hant`），其他语言则去掉地区后缀只保留语言代码。

2. **添加了 `updateSourceLanguage(from:)` 方法** — 在以下时机自动同步转录语言到翻译源语言：
   - 初始化时（`initialize()`）
   - 切换转录语言时（`switchLanguage(to:)`）
   - 开启翻译开关时（`onChange` of `isEnabled`）

3. **`updateConfiguration()` 不再接受 `nil` 源语言** — 如果 `sourceLanguage` 为 `nil`，直接不创建 session，避免触发自动检测弹窗。`source` 参数现在始终传入明确的语言值。