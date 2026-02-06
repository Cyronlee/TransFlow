import SwiftUI

/// Main transcription area showing completed sentences and volatile preview.
struct TranscriptionView: View {
    let sentences: [TranscriptionSentence]
    let partialText: String
    let partialTranslation: String
    let isTranslationEnabled: Bool

    @State private var scrollProxy: ScrollViewProxy?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    // Completed sentences
                    ForEach(sentences) { sentence in
                        SentenceRow(
                            sentence: sentence,
                            showTranslation: isTranslationEnabled
                        )
                    }

                    // Volatile preview (partial text)
                    if !partialText.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Divider()
                                .padding(.vertical, 4)

                            Text(partialText)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .italic()

                            if isTranslationEnabled && !partialTranslation.isEmpty {
                                Text(partialTranslation)
                                    .font(.callout)
                                    .foregroundStyle(.tertiary)
                                    .italic()
                            }
                        }
                    }

                    // Anchor for auto-scroll
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding()
            }
            .onChange(of: sentences.count) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: partialText) {
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }
}

/// A single completed sentence row with timestamp and optional translation.
struct SentenceRow: View {
    let sentence: TranscriptionSentence
    let showTranslation: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Timestamp
            Text(sentence.timestamp, format: .dateTime.hour().minute().second())
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)

            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text(sentence.text)
                    .font(.body)
                    .textSelection(.enabled)

                if showTranslation, let translation = sentence.translation, !translation.isEmpty {
                    Text(translation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }
}
