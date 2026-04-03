import SwiftUI

/// Main transcription area showing completed sentences history.
/// Only displays finalized sentences — volatile preview is shown in the bottom panel.
struct TranscriptionView: View {
    let sentences: [TranscriptionSentence]
    let isTranslationEnabled: Bool

    @State private var autoScroll = true

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(sentences) { sentence in
                            SentenceRow(
                                sentence: sentence,
                                showTranslation: isTranslationEnabled
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)

                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .onChange(of: sentences.count) {
                    if autoScroll {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }

            autoScrollToggle
        }
    }

    private var autoScrollToggle: some View {
        Button {
            autoScroll.toggle()
        } label: {
            Image(systemName: "chevron.down.2")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(autoScroll ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                )
        }
        .buttonStyle(.plain)
        .padding(.trailing, 16)
        .padding(.bottom, 12)
        .help(Text(autoScroll ? "transcription.auto_scroll_on" : "transcription.auto_scroll_off"))
    }
}

/// A single completed sentence row with timestamp, optional speaker, and optional translation.
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

            HStack(alignment: .firstTextBaseline, spacing: 10) {
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

                // Source badge (dual capture mode)
                if let source = sentence.source {
                    sourceBadge(source)
                }

                // Speaker badge
                if let speakerId = sentence.speakerId {
                    speakerBadge(speakerId)
                }

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

    private func sourceBadge(_ source: TranscriptionSource) -> some View {
        let label: String
        let color: Color
        switch source {
        case .microphone:
            label = String(localized: "source.mic")
            color = .blue
        case .systemAudio:
            label = String(localized: "source.system")
            color = .purple
        }
        return Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color.opacity(0.12))
            )
    }

    private func speakerBadge(_ speakerId: String) -> some View {
        let colorHex = SpeakerColor.color(for: speakerId)
        let displayName = SpeakerDisplayName.displayName(for: speakerId)

        return Text(displayName)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color(hex: colorHex))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(hex: colorHex).opacity(0.12))
            )
    }
}
