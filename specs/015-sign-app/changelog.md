脚本语法验证通过。下面总结一下改动。

---

## 改动总结

### 新增的 `--sign` 参数

你现在可以这样使用：

```bash
# 自动检测签名证书，没找到则使用 ad-hoc 签名
./scripts/build-dmg.sh --sign

# 指定签名身份
./scripts/build-dmg.sh --sign "Apple Development: your@email.com"
```

### 签名流程

脚本新增的签名流程会：

1. **自动检测签名身份** — 按优先级搜索：`Developer ID Application` > `Apple Development` > 任意可用证书 > 退回 ad-hoc (`-`)
2. **深度签名 .app** — 按正确顺序签名：
   - 内嵌 Frameworks（dylib、framework）
   - 辅助工具（MacOS 目录下的其他可执行文件）
   - 主 .app bundle
3. **签名 DMG** — 如果使用的是真实证书（非 ad-hoc），DMG 本身也会被签名
4. **验证签名** — 签名后自动运行 `codesign --verify` 验证
5. **输出签名状态** — 最终结果展示中显示签名状态

### 关于你的情况（有开发者账号但无付费会员）

你有两条路可走：

| 方式 | 命令 | 用户体验 |
|------|------|---------|
| **Ad-hoc 签名** | `--sign` | 保证完整性，但用户需右键→打开 |
| **免费开发证书** | 在 Xcode 登录 Apple ID，自动生成证书后用 `--sign` | 同上，但签名信息中会显示你的开发者身份 |

**获取免费开发证书的步骤**：
1. 打开 Xcode → Settings → Accounts → 添加你的 Apple ID
2. 选择你的 Team → Manage Certificates → 点 "+" → 创建 "Apple Development" 证书
3. 之后运行 `./scripts/build-dmg.sh --sign`，脚本会自动检测到这个证书

> **重要提示**：无论是 ad-hoc 还是免费开发证书签名，用户首次打开应用时都会看到 Gatekeeper 警告。只有付费的 `Developer ID Application` 证书 + 公证（Notarization）才能让用户无障碍打开应用。

应用已启动，系统应该会弹出麦克风权限请求弹窗了。请确认一下是否看到了弹窗？

## 总结：修复了两个 Bug

### Bug 1：签名时丢失 Entitlements（根本原因）

`build-dmg.sh` 的 `codesign_app` 函数在使用 `--sign` 时启用了 Hardened Runtime（`--options runtime`），但**没有自动传入 entitlements 文件**。这导致重签名后的 app 丢失了 `com.apple.security.device.audio-input` 权限声明，macOS 直接拒绝麦克风访问而不弹窗。

**修复**：脚本现在会自动检测并加载项目的 `TransFlow.entitlements` 文件。

### Bug 2：`set -euo pipefail` 导致签名检测静默失败

`detect_codesign_identity` 中的 `grep "Developer ID Application"` 在没有匹配时返回退出码 1，配合 `pipefail` 导致脚本直接退出，之前的 `--sign` 其实从来没有成功执行过签名。

**修复**：将 `security find-identity` 结果先存入变量，再用 `|| true` 安全地进行 grep 匹配。

### Bug 3（附带）：`cp -R` 安装丢失签名

`cp -R` 不会保留 macOS 的扩展属性（包括代码签名数据），应使用 `ditto` 或通过 DMG 安装。通过 DMG 拖拽到 `/Applications` 安装是正确的方式，所以这个不需要改脚本，但要注意不能用 `cp` 手动安装。