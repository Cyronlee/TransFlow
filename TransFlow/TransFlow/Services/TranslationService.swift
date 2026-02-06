@preconcurrency import Translation
import SwiftUI

/// Manages translation using Apple's Translation framework.
/// The TranslationSession is obtained via SwiftUI's `.translationTask` modifier.
@Observable
@MainActor
final class TranslationService {
    var isEnabled: Bool = false
    var sourceLanguage: Locale.Language?
    var targetLanguage: Locale.Language = Locale.Language(identifier: "zh-Hans")

    /// The translation configuration, set to nil and recreated to trigger new sessions.
    var configuration: TranslationSession.Configuration?

    private var session: TranslationSession?
    private var debounceTask: Task<Void, Never>?

    /// Currently translated partial text
    var currentPartialTranslation: String = ""

    /// Maps a transcription Locale (e.g. "en-US", "zh-Hans-CN") to a Translation Locale.Language.
    /// The Translation framework uses BCP 47 language tags without region (e.g. "en", "zh-Hans").
    static func translationLanguage(from transcriptionLocale: Locale) -> Locale.Language {
        let language = transcriptionLocale.language

        // For Chinese variants, preserve the script (Hans/Hant) which is critical
        if language.languageCode?.identifier == "zh" {
            if let script = language.script {
                return Locale.Language(identifier: "zh-\(script.identifier)")
            }
            // Fall back: check the full identifier for hints
            let id = transcriptionLocale.identifier
            if id.contains("Hans") {
                return Locale.Language(identifier: "zh-Hans")
            } else if id.contains("Hant") {
                return Locale.Language(identifier: "zh-Hant")
            }
            return Locale.Language(identifier: "zh-Hans")
        }

        // For all other languages, use just the language code (strip region)
        if let code = language.languageCode?.identifier {
            return Locale.Language(identifier: code)
        }

        return language
    }

    /// Update the source language from the transcription locale.
    /// Call this whenever the transcription language changes.
    func updateSourceLanguage(from transcriptionLocale: Locale) {
        sourceLanguage = Self.translationLanguage(from: transcriptionLocale)
        if isEnabled {
            updateConfiguration()
        }
    }

    /// Update the configuration to trigger a new translation session.
    func updateConfiguration() {
        guard isEnabled else {
            configuration = nil
            session = nil
            currentPartialTranslation = ""
            return
        }

        guard let source = sourceLanguage else {
            // No source language set — don't create a session (avoid auto-detect popup)
            return
        }

        // Avoid triggering if source and target are the same language
        if source.languageCode == targetLanguage.languageCode {
            return
        }

        if configuration != nil {
            configuration?.invalidate()
        }
        configuration = TranslationSession.Configuration(
            source: source,
            target: targetLanguage
        )
    }

    /// Called from `.translationTask` modifier when a new session is available.
    func handleSession(_ session: TranslationSession) async {
        // Prepare the translation session (downloads language pair if needed)
        nonisolated(unsafe) let prepSession = session
        do {
            try await prepSession.prepareTranslation()
        } catch {
            // Don't block — the session may still work for already-downloaded pairs
        }

        self.session = session
    }

    /// Clears the current session (e.g. when translation is disabled).
    func clearSession() {
        session = nil
        currentPartialTranslation = ""
        debounceTask?.cancel()
        debounceTask = nil
    }

    /// Translate a completed sentence.
    func translateSentence(_ text: String) async -> String? {
        guard isEnabled, let session else { return nil }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        nonisolated(unsafe) let currentSession = session
        do {
            let response = try await currentSession.translate(text)
            return response.targetText
        } catch {
            return nil
        }
    }

    /// Translate partial text with debounce (~300ms).
    func translatePartial(_ text: String) {
        debounceTask?.cancel()
        guard isEnabled, !text.isEmpty else {
            currentPartialTranslation = ""
            return
        }
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            if let translation = await translateSentence(text) {
                currentPartialTranslation = translation
            }
        }
    }

    /// Translate a batch of sentences.
    func translateBatch(_ texts: [String]) async -> [String?] {
        guard isEnabled, let session else {
            return Array(repeating: nil, count: texts.count)
        }
        nonisolated(unsafe) let currentSession = session
        var results: [String?] = []
        for text in texts {
            do {
                let response = try await currentSession.translate(text)
                results.append(response.targetText)
            } catch {
                results.append(nil)
            }
        }
        return results
    }
}
