import SwiftUI

/// Main transcription area showing completed sentences history.
/// Only displays finalized sentences — volatile preview is shown in the bottom panel.
struct TranscriptionView: View {
    let sentences: [TranscriptionSentence]
    let isTranslationEnabled: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sentences) { sentence in
                        SentenceRow(
                            sentence: sentence,
                            showTranslation: isTranslationEnabled
                        )
                    }

                    // Anchor for auto-scroll
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .onChange(of: sentences.count) {
                withAnimation(.easeOut(duration: 0.2)) {
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
        VStack(alignment: .leading, spacing: 0) {
            // Top separator line
            Rectangle()
                .fill(.quaternary.opacity(0.5))
                .frame(height: 0.5)
                .padding(.vertical, 10)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                // Timestamp badge
                Text(sentence.timestamp, format: .dateTime.hour().minute().second())
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(.quaternary.opacity(0.3))
                    )

                // Text content
                VStack(alignment: .leading, spacing: 4) {
                    Text(sentence.text)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .lineSpacing(3)

                    if showTranslation, let translation = sentence.translation, !translation.isEmpty {
                        Text(translation)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineSpacing(2)
                    }
                }
            }
        }
    }
}
