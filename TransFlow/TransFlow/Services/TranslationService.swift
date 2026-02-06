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

    /// Update the configuration to trigger a new translation session.
    func updateConfiguration() {
        guard isEnabled else {
            configuration = nil
            return
        }
        configuration?.invalidate()
        configuration = TranslationSession.Configuration(
            source: sourceLanguage,
            target: targetLanguage
        )
    }

    /// Called from `.translationTask` modifier when a new session is available.
    func setSession(_ session: TranslationSession) {
        self.session = session
    }

    /// Translate a completed sentence.
    func translateSentence(_ text: String) async -> String? {
        guard isEnabled, let session else { return nil }
        do {
            let response = try await session.translate(text)
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
        var results: [String?] = []
        for text in texts {
            do {
                let response = try await session.translate(text)
                results.append(response.targetText)
            } catch {
                results.append(nil)
            }
        }
        return results
    }
}
