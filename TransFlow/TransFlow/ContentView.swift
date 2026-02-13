import SwiftUI
import Translation

/// Main content view with history area on top and unified bottom panel
/// (live preview + controls).
///
/// The ViewModel is injected from `MainView` so it is created only once
/// at app launch — not every time the user navigates to this tab.
struct ContentView: View {
    @Bindable var viewModel: TransFlowViewModel
    @Bindable var floatingPreviewManager: FloatingPreviewPanelManager
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            // ── Top: Session bar ──
            SessionBarView(
                sessionName: viewModel.jsonlStore.currentSessionName
            ) { name in
                viewModel.createNewSession(name: name)
            }

            // ── Middle: Transcription history ──
            TranscriptionView(
                sentences: viewModel.sentences,
                isTranslationEnabled: viewModel.translationService.isEnabled
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // ── Bottom: Unified live preview + controls ──
            BottomPanelView(
                viewModel: viewModel,
                floatingPreviewManager: floatingPreviewManager,
                settings: settings
            )
        }
        .frame(minWidth: 640, minHeight: 460)
        // Translation session provider
        .translationTask(viewModel.translationService.configuration) { session in
            await viewModel.translationService.handleSession(session)
        }
        // Empty state
        .overlay {
            if viewModel.sentences.isEmpty && viewModel.currentPartialText.isEmpty {
                emptyStateView
            }
        }
        // Model not ready alert — prompts user to download in Settings
        .alert(
            "model_alert.title",
            isPresented: $viewModel.showModelNotReadyAlert
        ) {
            Button("model_alert.go_to_settings") {
                NotificationCenter.default.post(name: .navigateToSettings, object: nil)
            }
            Button("session.cancel", role: .cancel) {}
        } message: {
            Text("model_alert.message")
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
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(.quaternary)

            Text("empty_state.title")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            if !viewModel.micPermissionGranted {
                Label("empty_state.mic_permission", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.8))
            }
        }
        .allowsHitTesting(false)
        .offset(y: -40) // shift up slightly since bottom panel takes space
    }
}

// MARK: - Bottom Panel (Live Preview + Controls)

/// Unified bottom panel containing the live transcription preview and controls.
struct BottomPanelView: View {
    @Bindable var viewModel: TransFlowViewModel
    @Bindable var floatingPreviewManager: FloatingPreviewPanelManager
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            // Subtle top border
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)

            VStack(spacing: 12) {
                // ── Live transcription preview ──
                livePreviewSection

                // ── Controls row ──
                ControlBarView(
                    viewModel: viewModel,
                    floatingPreviewManager: floatingPreviewManager,
                    settings: settings
                )
            }
            .animation(.easeInOut(duration: 0.25), value: shouldShowPreview)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 14)
            .background(.background)
        }
    }

    private var shouldShowPreview: Bool {
        viewModel.listeningState == .active
            || viewModel.listeningState == .starting
            || !viewModel.currentPartialText.isEmpty
    }

    @ViewBuilder
    private var livePreviewSection: some View {
        if shouldShowPreview {
            LivePreviewContentView(
                partialText: viewModel.currentPartialText,
                partialTranslation: partialTranslationText,
                isListening: isListening
            )
            .transition(.opacity.combined(with: .move(edge: .bottom)))
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

#Preview {
    ContentView(
        viewModel: TransFlowViewModel(),
        floatingPreviewManager: FloatingPreviewPanelManager(),
        settings: AppSettings.shared
    )
}
