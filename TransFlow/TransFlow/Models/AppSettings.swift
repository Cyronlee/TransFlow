import SwiftUI

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

    /// The selected speech recognition engine.
    var selectedEngine: TranscriptionEngineKind {
        didSet {
            UserDefaults.standard.set(selectedEngine.rawValue, forKey: "selectedEngine")
        }
    }

    /// Selected local ASR model when `selectedEngine == .local`.
    var selectedLocalModel: LocalTranscriptionModelKind {
        didSet {
            UserDefaults.standard.set(selectedLocalModel.rawValue, forKey: "selectedLocalModel")
        }
    }

    /// The resolved locale used for SwiftUI environment.
    var locale: Locale

    private init() {
        let storedLang = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        let language = AppLanguage(rawValue: storedLang) ?? .system
        self.appLanguage = language

        let storedAppearance = UserDefaults.standard.string(forKey: "appAppearance") ?? "system"
        self.appAppearance = AppAppearance(rawValue: storedAppearance) ?? .system

        let storedEngine = UserDefaults.standard.string(forKey: "selectedEngine") ?? "apple"
        if storedEngine == "parakeetLocal" {
            // Backward compatibility for previous engine key.
            self.selectedEngine = .local
        } else {
            self.selectedEngine = TranscriptionEngineKind(rawValue: storedEngine) ?? .apple
        }

        let storedLocalModel = UserDefaults.standard.string(forKey: "selectedLocalModel")
            ?? LocalTranscriptionModelKind.parakeetOfflineInt8.rawValue
        self.selectedLocalModel = LocalTranscriptionModelKind(rawValue: storedLocalModel)
            ?? .parakeetOfflineInt8

        if let identifier = language.localeIdentifier {
            self.locale = Locale(identifier: identifier)
        } else {
            self.locale = Locale.current
        }
    }

    private func applyLanguage() {
        if let identifier = appLanguage.localeIdentifier {
            locale = Locale(identifier: identifier)
            // Override Apple's language array so Bundle lookups pick the right .lproj
            UserDefaults.standard.set([identifier], forKey: "AppleLanguages")
        } else {
            locale = Locale.current
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }
}
