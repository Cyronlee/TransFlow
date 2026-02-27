import SwiftUI

/// Content rendered inside the detachable floating preview panel.
struct FloatingPreviewView: View {
    @Bindable var viewModel: TransFlowViewModel
    @Bindable var panelManager: FloatingPreviewPanelManager
    @State private var isHovering = false

    private let captionBottomAnchor = "floating-caption-bottom"
    private let maxFinalizedSentenceCount = 4

    var body: some View {
        ZStack(alignment: .topTrailing) {
            captionCard
            controlOverlay
        }
        .padding(12)
        .frame(minWidth: 340, idealWidth: 390, minHeight: 96, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.16)) {
                isHovering = hovering
            }
        }
    }

    private var captionCard: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(captionLines) { line in
                        captionLineView(line)
                    }

                    Color.clear
                        .frame(height: 8)
                        .id(captionBottomAnchor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 80, maxHeight: .infinity)
            .padding(.trailing, 56)
            .onAppear {
                scrollToBottom(with: proxy, animated: false)
            }
            .onChange(of: captionLines) { _, _ in
                scrollToBottom(with: proxy)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var controlOverlay: some View {
        HStack(spacing: 8) {
            pinButton
            closeButton
        }
        // Keep controls out of the titlebar drag zone for reliable clicks.
        .padding(.top, 18)
        .padding(.trailing, 10)
        .opacity(shouldShowControls ? 1 : 0)
        .allowsHitTesting(shouldShowControls)
        .contentShape(Rectangle())
        .zIndex(5)
    }

    private var pinButton: some View {
        Button {
            panelManager.togglePin()
        } label: {
            Image(systemName: panelManager.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(panelManager.isPinned ? Color.accentColor : Color.secondary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .circle)
        .help(Text(panelManager.isPinned ? "floating_preview.unpin" : "floating_preview.pin"))
        .accessibilityLabel(Text(panelManager.isPinned ? "floating_preview.unpin" : "floating_preview.pin"))
    }

    private var closeButton: some View {
        Button {
            panelManager.close()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .circle)
        .help(Text("floating_preview.close"))
        .accessibilityLabel(Text("floating_preview.close"))
    }

    @ViewBuilder
    private func captionLineView(_ line: CaptionLine) -> some View {
        if line.isPartial {
            Text(line.text)
                .font(line.kind == .source ? .system(size: 15, weight: .regular) : .system(size: 12, weight: .regular))
                .foregroundStyle(lineForegroundStyle(for: line.kind))
                .italic()
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(line.text)
                .font(line.kind == .source ? .system(size: 15, weight: .regular) : .system(size: 12, weight: .regular))
                .foregroundStyle(lineForegroundStyle(for: line.kind))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func lineForegroundStyle(for kind: CaptionLine.Kind) -> AnyShapeStyle {
        switch kind {
        case .source:
            AnyShapeStyle(.primary)
        case .translation:
            AnyShapeStyle(.secondary)
        case .placeholder:
            AnyShapeStyle(.tertiary)
        }
    }

    private var captionLines: [CaptionLine] {
        let showTranslation = viewModel.translationService.isEnabled
        var lines: [CaptionLine] = []

        for sentence in viewModel.sentences.suffix(maxFinalizedSentenceCount) {
            let sourceText = sentence.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sourceText.isEmpty {
                lines.append(
                    CaptionLine(
                        id: "sentence-source-\(sentence.id.uuidString)",
                        text: sourceText,
                        kind: .source
                    )
                )
            }

            if showTranslation,
               let translation = sentence.translation?.trimmingCharacters(in: .whitespacesAndNewlines),
               !translation.isEmpty {
                lines.append(
                    CaptionLine(
                        id: "sentence-translation-\(sentence.id.uuidString)",
                        text: translation,
                        kind: .translation
                    )
                )
            }
        }

        let partialSource = viewModel.currentPartialText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !partialSource.isEmpty {
            lines.append(
                CaptionLine(
                    id: "partial-source",
                    text: partialSource,
                    kind: .source,
                    isPartial: true
                )
            )

            if showTranslation,
               let partialTranslationText,
               !partialTranslationText.isEmpty {
                lines.append(
                    CaptionLine(
                        id: "partial-translation",
                        text: partialTranslationText,
                        kind: .translation,
                        isPartial: true
                    )
                )
            }
        }

        if lines.isEmpty {
            let placeholderText = isListening
                ? String(localized: "control.listening")
                : String(localized: "control.start_transcription")
            lines.append(
                CaptionLine(
                    id: "placeholder",
                    text: placeholderText,
                    kind: .placeholder
                )
            )
        }

        return lines
    }

    private func scrollToBottom(with proxy: ScrollViewProxy, animated: Bool = true) {
        let action = { proxy.scrollTo(captionBottomAnchor, anchor: .bottom) }
        if animated {
            withAnimation(.easeOut(duration: 0.12)) {
                action()
            }
        } else {
            action()
        }
    }

    private var isListening: Bool {
        viewModel.listeningState == .active || viewModel.listeningState == .starting
    }

    private var shouldShowControls: Bool {
        isHovering || panelManager.isPinned
    }

    private var partialTranslationText: String? {
        guard viewModel.translationService.isEnabled else { return nil }
        let partial = viewModel.translationService.currentPartialTranslation
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return partial.isEmpty ? nil : partial
    }
}

private struct CaptionLine: Identifiable, Equatable {
    enum Kind: Equatable {
        case source
        case translation
        case placeholder
    }

    let id: String
    let text: String
    let kind: Kind
    var isPartial: Bool = false
}
