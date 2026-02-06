## DMG 打包脚本

### 新增文件

- **`scripts/build-dmg.sh`** — 一键 DMG 打包脚本，基于 [create-dmg](https://github.com/create-dmg/create-dmg) 工具
- **`scripts/dmg/background.png`** — 默认 DMG 背景图（600x400，深色渐变）

### 打包流程

1. `xcodebuild` 以 Release 配置构建 TransFlow.app
2. 将 .app 复制到临时 DMG 准备目录
3. `create-dmg` 创建带背景图、应用图标、Applications 快捷方式的 DMG 安装镜像
4. 自动从 Info.plist 读取版本号，输出 `build/TransFlow-{version}.dmg`

### 脚本参数

| 参数 | 说明 |
|------|------|
| `--clean` | 先 clean 再构建 |
| `--skip-build` | 跳过构建，使用已有 .app |
| `--open` | 打包后自动打开 DMG |
| `--codesign ID` | 对 DMG 进行代码签名 |

### DMG 外观配置

- 窗口尺寸 600x400，居中显示 app 图标和 Applications 拖放链接
- 支持自定义背景图（`scripts/dmg/background.png`）和卷图标（`scripts/dmg/volume-icon.icns`）
- 隐藏 .app 扩展名，图标尺寸 100px

### 容错处理

- `create-dmg` 退出码 2（美化失败但 DMG 已创建）视为成功
- unmount 失败时自动 fallback：强制 detach 后手动 `hdiutil convert` 转换 rw DMG 为最终压缩格式

### 其他

- `.gitignore` 新增 `build/` 和 `*.dmg` 忽略规则
- 依赖：`brew install create-dmg`
