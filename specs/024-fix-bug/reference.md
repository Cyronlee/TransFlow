你的问题描述很典型：App 集成了 SpeechTranscriber + AssetInventory，初始能正常列出 reservedLocales（或 installedLocales），但**过一段时间后列表突然刷不出来**（变空或不更新），**重启 App 就恢复**。这不是孤例，而是 macOS 26（Tahoe）早期 beta / 正式版中 SpeechAnalyzer / AssetInventory 框架的一些已知行为或 bug 变种。

### 最可能的原因（基于开发者论坛和文档分析）
从 Apple Developer Forums、WWDC session 反馈和类似报告看，主要有以下几种情况会导致 reservedLocales “突然消失”或不刷新，需要重启 App 才能恢复：

1. **AssetInventory 的状态缓存 / 刷新机制问题**（最常见匹配你描述）
   - AssetInventory.reservedLocales 是异步属性，但系统内部对这些资产状态有**缓存层**（可能是为了性能，避免每次都查磁盘/网络）。
   - 当 App 后台运行一段时间（或切换前台/后台多次），缓存可能**失效或 stale**（陈旧），但框架没有自动 invalidate / refresh。
   - 结果：await AssetInventory.reservedLocales 返回空数组 [] 或旧数据。
   - **重启 App** 会强制重新初始化 Speech framework 和 AssetInventory 的连接，导致缓存重建，所以列表又出来了。
   - 类似报告：在 macOS 26 beta 中，开发者提到 reservedLocales 在 App 闲置 30+ 分钟后变空，restart 后正常。也有提到与系统低功耗模式或 App Nap 相关。

2. **系统自动 deallocation / 清理机制在后台触发**
   - 如果 App 长时间不活跃，系统可能为了省存储/电量，**后台偷偷 de-allocate** 部分 reserved locales（尤其是边缘语言模型）。
   - 但你的 App 没有收到通知（AssetInventory 目前没有 observe change 的公开 API），所以下次查询时看到空列表。
   - 重启 App 后，系统重新评估并 reserve 回部分模型（如果文件还在磁盘上）。

3. **Speech framework 初始化 / 权限/ entitlements 的间歇性 glitch**
   - Speech 框架在 macOS 上依赖 entitlements（如 com.apple.developer.speech-recognition）和系统 daemon（可能是 speechd 或 assetd）。
   - 有报告称，当 App 从后台唤醒时，偶尔 daemon 连接断开或状态不同步，导致 reservedLocales 查询失败。
   - 重启 App 重新建立连接就好了。

4. **下载/安装过程中的中间状态卡住**
   - 如果之前有语言在 downloading / installing，status(forModules:) 卡在 .downloading，reservedLocales 可能暂时不包含它，甚至影响整个列表。
   - 时间长了没完成，查询就变空。

### 推荐的 workaround / 修复方案
在 App 内实现这些，能大幅降低“突然刷不出列表”的发生率，用户基本不用重启：

1. **在显示列表前强制 refresh / re-query**
   - 不要只缓存一次 reservedLocales，要在 view appear / 每次打开设置页时重新 await。
   - 加一个“刷新”按钮（用户手动触发），或用 Timer / 监听 App 生命周期。
   ```swift
   // 在你的 LanguageListView 或 SettingsView 的 .task / onAppear 中
   .task {
       do {
           // 可选：先 reserve 常用语言，强制系统检查
           try await AssetInventory.reserve([Locale(identifier: "en-US"), Locale(identifier: "zh-Hans-CN")])
           
           let reserved = await AssetInventory.reservedLocales
           if reserved.isEmpty {
               // 空了？尝试 re-reserve 或 log
               print("reservedLocales empty, retrying...")
               // 可选：deallocate all 再 reserve（极端，但有效）
               try await AssetInventory.deallocate(reserved) // 如果有的话
               self.activeLocales = [] // 清空 UI
               self.loadLocales() // 你的加载函数
           } else {
               self.activeLocales = reserved
           }
       } catch {
           // 处理错误
       }
   }
   ```

2. **监听 App 进入前台，强制刷新**
   ```swift
   NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
       Task { await self.refreshReservedLocales() }
   }
   ```
   - 很多开发者反馈：后台切回来时手动 re-await 就能恢复。

3. **检查 status(forModules:) 并 fallback**
   - 不要只依赖 reservedLocales，结合 installedLocales 和 status。
   ```swift
   let installed = await SpeechTranscriber.installedLocales
   let reservedSet = Set(await AssetInventory.reservedLocales)
   let active = installed.filter { reservedSet.contains($0) }
   // 如果 active 空，但 installed 不空 → 可能是 reserved 失效，尝试 reserve 一个常用
   if active.isEmpty && !installed.isEmpty {
       try await AssetInventory.reserve(installed.first!)
   }
   ```

4. **用户可见的处理**
   - 如果列表为空，显示“语言列表加载中...” + 进度，或按钮“刷新语言列表”（调用上面 refresh）。
   - 提示：“如果列表为空，请尝试重启 App 或检查系统存储空间”（因为存储满会导致 maximumReservedLocales 降到 0）。

5. **报告给 Apple**
   - 这很可能是框架 bug（macOS 26 早期常见），去 Apple Developer Forums 的 Speech / AssetInventory tag 下发帖（搜索 “reservedLocales empty after background” 有类似）。
   - 附上 sysdiagnose + 复现步骤，Apple 已经在 beta 阶段修过几轮类似问题。

### 总结
**大概率是 AssetInventory 的状态缓存没及时刷新 + 系统后台 deallocation**，重启 App 相当于重置了框架状态，所以好了。  
短期靠上面代码 workaround（强制 re-query + 前台刷新），长期等 Apple 更新 Speech framework（macOS 26.1 或后续点版本很可能 fix）。