import SwiftUI
import Carbon.HIToolbox

/// Supported app languages for the UI.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .system: "language.system"
        case .english: "language.en"
        case .chinese: "language.zh-Hans"
        }
    }

    /// The locale override to apply, or nil for system default.
    var localeIdentifier: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .chinese: "zh-Hans"
        }
    }
}

/// Supported appearance modes.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .system: "appearance.system"
        case .light: "appearance.light"
        case .dark: "appearance.dark"
        }
    }

    /// The SwiftUI color scheme override, or nil for system default.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Centralized app settings persisted via UserDefaults.
@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    /// The user-chosen app language.
    var appLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(appLanguage.rawValue, forKey: "appLanguage")
            applyLanguage()
        }
    }

    /// The user-chosen appearance mode.
    var appAppearance: AppAppearance {
        didSet {
            UserDefaults.standard.set(appAppearance.rawValue, forKey: "appAppearance")
        }
    }

    /// The resolved locale used for SwiftUI environment.
    var locale: Locale

    /// Font size for source text in the floating preview panel.
    var floatingPanelFontSize: CGFloat {
        didSet {
            UserDefaults.standard.set(Double(floatingPanelFontSize), forKey: "floatingPanelFontSize")
        }
    }

    /// Translation text is rendered proportionally smaller.
    var floatingPanelTranslationFontSize: CGFloat {
        (floatingPanelFontSize * 0.8).rounded()
    }

    private var isInitialized = false

    private init() {
        let storedLang = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        let language = AppLanguage(rawValue: storedLang) ?? .system
        self.appLanguage = language

        let storedAppearance = UserDefaults.standard.string(forKey: "appAppearance") ?? "system"
        self.appAppearance = AppAppearance(rawValue: storedAppearance) ?? .system

        if let identifier = language.localeIdentifier {
            self.locale = Locale(identifier: identifier)
        } else {
            self.locale = Locale.current
        }

        self.diarizationSensitivity = UserDefaults.standard.object(forKey: "diarizationSensitivity") as? Double ?? 0.8

        self.videoSourceLanguage = UserDefaults.standard.string(forKey: "videoSourceLanguage") ?? "en"
        self.videoEnableTranslation = UserDefaults.standard.bool(forKey: "videoEnableTranslation")
        self.videoTargetLanguage = UserDefaults.standard.string(forKey: "videoTargetLanguage") ?? "zh-Hans"
        self.videoEnableDiarization = UserDefaults.standard.object(forKey: "videoEnableDiarization") as? Bool ?? true
        let storedFontSize = UserDefaults.standard.double(forKey: "floatingPanelFontSize")
        self.floatingPanelFontSize = storedFontSize > 0
            ? CGFloat(storedFontSize)
            : Self.recommendedFloatingPanelFontSize()

        self.hotkeyToggleTranscription = .empty
        self.hotkeyToggleTranslation = .empty
        self.hotkeyToggleFloatingPreview = .empty
        self.hotkeyToggleMainWindow = .empty

        self.hotkeyToggleTranscription = loadHotkey(forKey: "hotkey.toggleTranscription")
        self.hotkeyToggleTranslation = loadHotkey(forKey: "hotkey.toggleTranslation")
        self.hotkeyToggleFloatingPreview = loadHotkey(forKey: "hotkey.toggleFloatingPreview")
        self.hotkeyToggleMainWindow = loadHotkey(forKey: "hotkey.toggleMainWindow")

        self.isInitialized = true
    }

    // MARK: - Diarization Settings

    /// Speaker separation sensitivity (maps to OfflineDiarizerConfig.clusteringThreshold).
    /// Higher = more aggressive splitting (more speakers). Range: 0.5 – 0.95.
    var diarizationSensitivity: Double {
        didSet {
            UserDefaults.standard.set(diarizationSensitivity, forKey: "diarizationSensitivity")
        }
    }

    // MARK: - Video Transcription Config (remembered across sessions)

    var videoSourceLanguage: String {
        didSet { UserDefaults.standard.set(videoSourceLanguage, forKey: "videoSourceLanguage") }
    }
    var videoEnableTranslation: Bool {
        didSet { UserDefaults.standard.set(videoEnableTranslation, forKey: "videoEnableTranslation") }
    }
    var videoTargetLanguage: String {
        didSet { UserDefaults.standard.set(videoTargetLanguage, forKey: "videoTargetLanguage") }
    }
    var videoEnableDiarization: Bool {
        didSet { UserDefaults.standard.set(videoEnableDiarization, forKey: "videoEnableDiarization") }
    }

    // MARK: - Hotkey Bindings

    var hotkeyToggleTranscription: HotkeyBinding {
        didSet {
            saveHotkey(hotkeyToggleTranscription, forKey: "hotkey.toggleTranscription")
            if isInitialized { GlobalHotkeyManager.shared.refreshCachedBindings() }
        }
    }
    var hotkeyToggleTranslation: HotkeyBinding {
        didSet {
            saveHotkey(hotkeyToggleTranslation, forKey: "hotkey.toggleTranslation")
            if isInitialized { GlobalHotkeyManager.shared.refreshCachedBindings() }
        }
    }
    var hotkeyToggleFloatingPreview: HotkeyBinding {
        didSet {
            saveHotkey(hotkeyToggleFloatingPreview, forKey: "hotkey.toggleFloatingPreview")
            if isInitialized { GlobalHotkeyManager.shared.refreshCachedBindings() }
        }
    }
    var hotkeyToggleMainWindow: HotkeyBinding {
        didSet {
            saveHotkey(hotkeyToggleMainWindow, forKey: "hotkey.toggleMainWindow")
            if isInitialized { GlobalHotkeyManager.shared.refreshCachedBindings() }
        }
    }

    // MARK: - Floating Panel Font Size

    static func recommendedFloatingPanelFontSize() -> CGFloat {
        guard let screen = NSScreen.main else { return 15 }
        let scale = screen.backingScaleFactor
        let logicalHeight = screen.frame.height

        if scale < 1.5 && logicalHeight > 1200 {
            return 20
        } else if scale < 1.5 {
            return 17
        }
        return 15
    }

    func adjustFloatingPanelFontSize(by delta: CGFloat) {
        let newSize = floatingPanelFontSize + delta
        floatingPanelFontSize = min(max(newSize, 10), 28)
    }

    private func applyLanguage() {
        if let identifier = appLanguage.localeIdentifier {
            locale = Locale(identifier: identifier)
            UserDefaults.standard.set([identifier], forKey: "AppleLanguages")
        } else {
            locale = Locale.current
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }

    private func loadHotkey(forKey key: String) -> HotkeyBinding {
        guard let data = UserDefaults.standard.data(forKey: key),
              let binding = try? JSONDecoder().decode(HotkeyBinding.self, from: data)
        else { return .empty }
        return binding
    }

    private func saveHotkey(_ binding: HotkeyBinding, forKey key: String) {
        if let data = try? JSONEncoder().encode(binding) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Hotkey Binding Model

struct HotkeyBinding: Codable, Equatable {
    var keyCode: UInt16?
    var modifiers: UInt

    static let empty = HotkeyBinding(keyCode: nil, modifiers: 0)

    var isEmpty: Bool { keyCode == nil }

    init(keyCode: UInt16?, modifiers: UInt) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    var nsEventModifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
    }

    var displayString: String {
        guard let keyCode else { return "" }
        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined()
    }

    func matches(_ event: NSEvent) -> Bool {
        guard let keyCode else { return false }
        let relevantMask: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
        return event.keyCode == keyCode
            && event.modifierFlags.intersection(relevantMask) == NSEvent.ModifierFlags(rawValue: modifiers).intersection(relevantMask)
    }

    static func keyName(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_ForwardDelete: return "⌦"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
            let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
            guard let data = layoutData else {
                return "?"
            }
            let layout = unsafeBitCast(data, to: CFData.self) as Data
            var deadKeyState: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            layout.withUnsafeBytes { ptr in
                guard let base = ptr.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
                UCKeyTranslate(
                    base,
                    keyCode,
                    UInt16(kUCKeyActionDisplay),
                    0,
                    UInt32(LMGetKbdType()),
                    UInt32(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState,
                    4,
                    &length,
                    &chars
                )
            }
            if length > 0 {
                return String(utf16CodeUnits: chars, count: length).uppercased()
            }
            return "?"
        }
    }
}
