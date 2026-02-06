import SwiftUI
import Translation

/// Main content view combining transcription area and control bar.
struct ContentView: View {
    @State private var viewModel = TransFlowViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Transcription area (fills most of the window)
            TranscriptionView(
                sentences: viewModel.sentences,
                partialText: viewModel.currentPartialText,
                partialTranslation: viewModel.translationService.currentPartialTranslation,
                isTranslationEnabled: viewModel.translationService.isEnabled
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Bottom control bar
            ControlBarView(viewModel: viewModel)
        }
        .frame(minWidth: 600, minHeight: 400)
        // Translation session provider — this is the ONLY way to obtain a TranslationSession
        .translationTask(viewModel.translationService.configuration) { session in
            viewModel.translationService.setSession(session)
        }
        // Empty state
        .overlay {
            if viewModel.sentences.isEmpty && viewModel.currentPartialText.isEmpty {
                emptyStateView
            }
        }
        // Menu command handlers
        .onReceive(NotificationCenter.default.publisher(for: .clearHistory)) { _ in
            viewModel.clearHistory()
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportSRT)) { _ in
            Task {
                await viewModel.exportSRT()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)

            Text("Press Start to begin transcription")
                .font(.title3)
                .foregroundStyle(.secondary)

            if !viewModel.micPermissionGranted {
                Text("Microphone permission is required")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    ContentView()
}
