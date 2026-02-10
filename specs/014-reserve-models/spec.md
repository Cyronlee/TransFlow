修复下面的报错
```
──────────────────────────────────────
TransFlow Error Log
Version: 1.0.0 (1)
macOS: Version 26.2 (Build 25C56)
Launch: 2026-02-09 07:20:56 +0000
──────────────────────────────────────
[2026-02-09 15:21:15.836] [SpeechModel] Model download failed for zh_HK: Too many allocated locales, 5 maximum.  (TransFlow/SpeechModelManager.swift:210)
```

复现步骤
```
Given进入设置页面
when 下了5个包，点击下载第六个
Then APPLE API报错 too many allocated locales, 5 maximum.
```

我认为speech模型不应该限制下载个数，因为使用的时候只会指定一个