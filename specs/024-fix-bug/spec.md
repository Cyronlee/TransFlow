## 修复语音模型闲置后失效 Bug

### 问题描述

每次启动时转写功能正常，但 app 闲置一段时间（30+ 分钟）后：
- 再次转录报错 "model not ready"
- 下拉选中的转写模型消失
- 设置页激活模型无反应
- 重启 app 恢复正常

### 根因

macOS 26 `AssetInventory` 框架的已知问题：
1. AssetInventory 内部缓存在 app 闲置后过期（stale），`reservedLocales` 返回空，`status(forModules:)` 把已安装模型报告为"未下载"
2. 系统可能在后台自动 deallocate reserved locales，但不通知 app
3. Speech 框架 daemon 连接可能在后台断开

### 修复方案

- [x] `SpeechModelManager` 监听 `NSApplication.didBecomeActiveNotification`，前台激活时重新验证所有已知模型状态
- [x] 检测 stale cache（原来 installed 现在变了）时，通过 `AssetInventory.reserve()` 强制系统刷新
- [x] `ensureModelReady()` 在首次 check 返回 `notDownloaded` 时先尝试 re-reserve + re-check，避免不必要的重新下载
- [x] `TransFlowViewModel` 监听前台激活，空闲时刷新当前语言模型状态
- [x] `SettingsView` 每次进入时重新查询模型状态（而非仅首次加载）

### 日志与文档

- [x] 在 `SpeechModelManager`、`TransFlowViewModel`、`SpeechEngine` 添加关键生命周期日志
- [x] 创建 `docs/speech-model-lifecycle.md` 作为 AI agent 参考文档
- [x] 创建 `.cursor/rules/speech-model-lifecycle.mdc` cursor rule
- [x] 更新 `.cursor/rules/global-rules.mdc` 引用文档
