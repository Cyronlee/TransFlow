import SwiftUI

/// Content rendered inside the detachable floating preview panel.
struct FloatingPreviewView: View {
    @Bindable var viewModel: TransFlowViewModel
    @Bindable var panelManager: FloatingPreviewPanelManager

    var body: some View {
        VStack(spacing: 10) {
            toolbar

            LivePreviewContentView(
                partialText: viewModel.currentPartialText,
                partialTranslation: partialTranslationText,
                isListening: isListening,
                idleTextKey: "control.start_transcription"
            )
        }
        .padding(12)
        .frame(minWidth: 320, idealWidth: 380, minHeight: 140, alignment: .topLeading)
        .background(.background)
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
                    .frame(width: 22, height: 22)
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
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.quaternary.opacity(0.45))
                    )
            }
            .buttonStyle(.plain)
            .help(Text("floating_preview.close"))
            .accessibilityLabel(Text("floating_preview.close"))
        }
    }

    private var isListening: Bool {
        viewModel.listeningState == .active || viewModel.listeningState == .starting
    }

    private var partialTranslationText: String? {
        guard viewModel.translationService.isEnabled else { return nil }
        let partial = viewModel.translationService.currentPartialTranslation
        return partial.isEmpty ? nil : partial
    }
}
