import AppKit
import Foundation

/// Manages global keyboard shortcuts via a CGEvent tap.
/// Requires macOS Accessibility permission (AXIsProcessTrusted).
@MainActor
@Observable
final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    /// Whether the app has accessibility permission (observed by settings UI).
    var isAccessibilityGranted: Bool = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var healthCheckTask: Task<Void, Never>?
    private var isInitialized = false

    /// Action callbacks, set once from TransFlowApp.
    private var actions: [() -> Void] = Array(repeating: {}, count: 4)

    /// Thread-safe binding cache read by the CGEvent callback.
    nonisolated(unsafe) static var cachedBindings: [CachedBinding] = []

    struct CachedBinding: Sendable {
        let keyCode: UInt16
        let modifiers: UInt
        let actionIndex: Int
    }

    private init() {
        isAccessibilityGranted = AXIsProcessTrusted()
    }

    // MARK: - Public

    func configure(
        onToggleTranscription: @escaping () -> Void,
        onToggleTranslation: @escaping () -> Void,
        onToggleFloatingPreview: @escaping () -> Void,
        onToggleMainWindow: @escaping () -> Void
    ) {
        actions = [onToggleTranscription, onToggleTranslation, onToggleFloatingPreview, onToggleMainWindow]
        refreshCachedBindings()
    }

    /// Rebuild the static binding cache from current AppSettings.
    func refreshCachedBindings() {
        let s = AppSettings.shared
        let pairs: [(HotkeyBinding, Int)] = [
            (s.hotkeyToggleTranscription, 0),
            (s.hotkeyToggleTranslation, 1),
            (s.hotkeyToggleFloatingPreview, 2),
            (s.hotkeyToggleMainWindow, 3),
        ]
        Self.cachedBindings = pairs.compactMap { b, i in
            guard let kc = b.keyCode else { return nil }
            return CachedBinding(keyCode: kc, modifiers: b.modifiers, actionIndex: i)
        }
    }

    func start() {
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            self.setupWithRetry()
        }
    }

    func reinitialize() {
        healthCheckTask?.cancel()
        isInitialized = false
        cleanupEventTap()
        setupWithRetry()
    }

    func requestAccessibility() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
        pollAccessibility()
    }

    // MARK: - Dispatch (called from main queue)

    func dispatchAction(index: Int) {
        guard actions.indices.contains(index) else { return }
        actions[index]()
    }

    // MARK: - Setup

    private func setupWithRetry() {
        for attempt in 1...5 {
            if setupEventTap() {
                isInitialized = true
                startHealthCheck()
                return
            }
            if attempt < 5 { Thread.sleep(forTimeInterval: 0.3) }
        }
    }

    @discardableResult
    private func setupEventTap() -> Bool {
        cleanupEventTap()

        let trusted = AXIsProcessTrusted()
        isAccessibilityGranted = trusted
        guard trusted else { return false }

        let mask: CGEventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                // Re-enable on system disable
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let refcon {
                        let mgr = Unmanaged<GlobalHotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                        DispatchQueue.main.async { mgr.reinitialize() }
                    }
                    return Unmanaged.passUnretained(event)
                }

                guard type == .keyDown else { return Unmanaged.passUnretained(event) }

                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = event.flags

                var mods: NSEvent.ModifierFlags = []
                if flags.contains(.maskCommand) { mods.insert(.command) }
                if flags.contains(.maskAlternate) { mods.insert(.option) }
                if flags.contains(.maskControl) { mods.insert(.control) }
                if flags.contains(.maskShift) { mods.insert(.shift) }
                let relevant: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
                let eventMods = mods.intersection(relevant)

                for binding in GlobalHotkeyManager.cachedBindings {
                    let bMods = NSEvent.ModifierFlags(rawValue: binding.modifiers).intersection(relevant)
                    if keyCode == binding.keyCode && eventMods == bMods {
                        let idx = binding.actionIndex
                        if let refcon {
                            let mgr = Unmanaged<GlobalHotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                            DispatchQueue.main.async { mgr.dispatchAction(index: idx) }
                        }
                        return nil // consume the event
                    }
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap else { return false }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return false }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source

        return CGEvent.tapIsEnabled(tap: tap)
    }

    private func cleanupEventTap() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - Health Check

    private func startHealthCheck() {
        healthCheckTask?.cancel()
        healthCheckTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { break }
                guard let tap = self.eventTap else { self.setupWithRetry(); continue }
                if !CGEvent.tapIsEnabled(tap: tap) {
                    CGEvent.tapEnable(tap: tap, enable: true)
                    if !CGEvent.tapIsEnabled(tap: tap) { self.setupWithRetry() }
                }
            }
        }
    }

    // MARK: - Accessibility Polling

    private func pollAccessibility() {
        Task {
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let trusted = AXIsProcessTrusted()
                if trusted != self.isAccessibilityGranted {
                    self.isAccessibilityGranted = trusted
                    if trusted { self.reinitialize() }
                }
                if self.isAccessibilityGranted { break }
            }
        }
    }
}
