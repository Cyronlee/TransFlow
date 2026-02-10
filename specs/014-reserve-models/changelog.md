Build 成功，修复完成。以下是问题分析和修复总结：

## 问题原因

Apple 的 `AssetInventory.reserve(locale:)` API 限制每个 app 最多保留 **5 个** locale 预留槽位（`maximumReservedLocales`）。原代码在每次下载模型时都调用 `reserve`，但从不释放旧的预留，因此下载第 6 个模型时触发 "Too many allocated locales, 5 maximum" 错误。

## 关键认知

根据 Apple 文档，`reserve` 只是一个"预留槽位"的概念，**已下载的模型作为系统共享资源会持久保存**，释放预留并不会删除已下载的模型。因此我们可以放心地在下载新模型前释放旧的预留。

## 修改内容

在 `SpeechModelManager.swift` 中新增了 `ensureReservationSlotAvailable(excluding:)` 方法：

```83:98:TransFlow/TransFlow/Services/SpeechModelManager.swift
    private func ensureReservationSlotAvailable(excluding locale: Locale) async {
        let reserved = await AssetInventory.reservedLocales
        guard reserved.count >= AssetInventory.maximumReservedLocales else { return }

        // Release reservations that are not currently being downloaded
        for reservedLocale in reserved {
            // Don't release the locale we're about to reserve
            if reservedLocale.identifier == locale.identifier { continue }
            // Don't release a locale that is currently downloading
            if let downloading = downloadingLocale, downloading.identifier == reservedLocale.identifier { continue }

            await AssetInventory.release(reservedLocale: reservedLocale)
            // One slot freed is enough
            break
        }
    }
```

并在 `downloadModel` 的 `reserve` 调用前插入：

```208:209:TransFlow/TransFlow/Services/SpeechModelManager.swift
            // Free up a reservation slot if we're at the limit
            await ensureReservationSlotAvailable(excluding: supportedLocale)
```

这样用户可以下载任意数量的语音模型，不再受 5 个预留槽位的限制。