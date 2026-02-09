## 崩溃原因

**异常类型**: `EXC_BREAKPOINT (SIGTRAP)` — Apple Translation 框架内部的 `_assertionFailure`

**根因**: `TranslationSession` 在已被 `invalidate()` 或置为 `nil` 后，仍被正在执行的 `translateSentence` 异步任务持有并调用 `translate()`。具体场景：

1. `translateSentence` 获取 `session` 引用，通过 `nonisolated(unsafe)` 逃逸出 MainActor 隔离
2. `await session.translate(text)` 挂起期间，主线程执行了 `updateConfiguration()` 或 `clearSession()`，导致 `configuration?.invalidate()` 使旧 session 失效
3. 挂起恢复后，已失效的 session 继续执行翻译，触发 Translation 框架内部断言崩溃

## 修复内容 (`TranslationService.swift`)

1. **移除 `nonisolated(unsafe)`** — 不再通过不安全方式逃逸 session 引用，保持 MainActor 隔离
2. **新增 `activeTranslationTasks` 追踪** — 记录所有进行中的翻译任务（`[UUID: Task]`）
3. **session 失效时取消所有翻译** — `updateConfiguration()` 和 `clearSession()` 中调用 `cancelAllTranslations()`，确保旧 session 上不会继续执行翻译
4. **`updateConfiguration()` 中先清空 session** — invalidate 旧 configuration 后立即将 `session` 置为 `nil`，防止新翻译使用旧 session
5. **`translateSentence` 使用 `withTaskCancellationHandler`** — 翻译前后均检查 `Task.isCancelled`，被取消时安全返回 `nil`
6. **`translateBatch` 改为复用 `translateSentence`** — 避免重复的 `nonisolated(unsafe)` 代码，统一走安全路径