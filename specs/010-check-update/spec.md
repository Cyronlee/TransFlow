实现基于github release的检查更新功能

只在每次打开app时检查一次

通过 https://github.com/Cyronlee/TransFlow/releases 获取最新版本号

如果发现有新版本，不要弹出更新提示框，只在设置页面版本号区域提醒，点击可以跳转到github release页面手动下载新版本

如果当前版本为最新版本，则显示已经最新标识

注意离线时不检查，报错要捕获不要影响用户