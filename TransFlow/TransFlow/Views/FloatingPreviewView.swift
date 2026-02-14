import SwiftUI

/// Content rendered inside the detachable floating preview panel.
struct FloatingPreviewView: View {
    @Bindable var viewModel: TransFlowViewModel
    @Bindable var panelManager: FloatingPreviewPanelManager

    var body: some View {
        VStack(spacing: 10) {
            toolbar

            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("floating_preview.last_section")
                lastSentenceCard

                sectionHeader("floating_preview.live_section")
                LivePreviewContentView(
                    partialText: viewModel.currentPartialText,
                    partialTranslation: partialTranslationText,
                    isListening: isListening,
                    idleTextKey: "control.start_transcription",
                    usesGlassStyle: true,
                    maxContentHeight: 110,
                    allowsScrolling: true,
                    prioritizeNewestText: true
                )
            }
        }
        .padding(12)
        .frame(minWidth: 340, idealWidth: 390, minHeight: 210, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 10)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("floating_preview.title")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Button {
                panelManager.togglePin()
            } label: {
                Image(systemName: panelManager.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(panelManager.isPinned ? Color.accentColor : Color.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.quaternary.opacity(panelManager.isPinned ? 0.38 : 0.25))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 0.6)
                    )
            }
            .buttonStyle(.plain)
            .help(Text(panelManager.isPinned ? "floating_preview.unpin" : "floating_preview.pin"))
            .accessibilityLabel(Text(panelManager.isPinned ? "floating_preview.unpin" : "floating_preview.pin"))

            Button {
                panelManager.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.quaternary.opacity(0.3))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 0.6)
                    )
            }
            .buttonStyle(.plain)
            .help(Text("floating_preview.close"))
            .accessibilityLabel(Text("floating_preview.close"))
        }
    }

    private func sectionHeader(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 11, weight: .semibold))
            .textCase(.uppercase)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var lastSentenceCard: some View {
        if let lastSentence = viewModel.sentences.last {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lastSentence.text)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let translation = lastSentenceTranslation, !translation.isEmpty {
                        Text(translation)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 110, alignment: .topLeading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.6)
            )
        } else {
            Text("floating_preview.no_last_sentence")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.regularMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.6)
                )
        }
    }

    private var isListening: Bool {
        viewModel.listeningState == .active || viewModel.listeningState == .starting
    }

    private var lastSentenceTranslation: String? {
        guard viewModel.translationService.isEnabled else { return nil }
        return viewModel.sentences.last?.translation
    }

    private var partialTranslationText: String? {
        guard viewModel.translationService.isEnabled else { return nil }
        let partial = viewModel.translationService.currentPartialTranslation
        return partial.isEmpty ? nil : partial
    }
}
